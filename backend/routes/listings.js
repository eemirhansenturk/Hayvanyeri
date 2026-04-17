const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const Listing = require('../models/Listing');
const Notification = require('../models/Notification');
const User = require('../models/User');
const auth = require('../middleware/auth');
const fs = require('fs');
const sharp = require('sharp');

// Klasörü oluştur (yoksa)
const uploadDir = 'uploads/ilanlar/';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// Multer yapılandırması
const storage = multer.memoryStorage();
const upload = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 } });

// Tüm ilanları getir (sayfalama destekli)
router.get('/', async (req, res) => {
  try {
    const { 
      category, listingType, city, district, search,
      animalType, breed, gender, age, weight, healthStatus,
      minPrice, maxPrice, minAge, maxAge, minWeight, maxWeight,
      page, limit, sort
    } = req.query;

    const pageNum  = Math.max(1, parseInt(page)  || 1);
    const limitNum = Math.min(50, Math.max(1, parseInt(limit) || 10));
    const skip     = (pageNum - 1) * limitNum;
    
    let query = { status: 'aktif' };
    
    if (category) query.category = category;
    if (listingType) query.listingType = listingType;
    if (city) query['location.city'] = { $regex: city, $options: 'i' };
    if (district) query['location.district'] = { $regex: district, $options: 'i' };
    if (animalType) {
      query.animalType = { $in: animalType.split(',') };
    }
    if (breed) {
      query.breed = { $in: breed.split(',') };
    }
    if (gender) query.gender = gender;
    if (age) query.age = age;
    if (weight) query.weight = weight;
    if (healthStatus) query.healthStatus = { $regex: healthStatus, $options: 'i' };

    if (minPrice || maxPrice) {
      query.price = {};
      if (minPrice) query.price.$gte = Number(minPrice);
      if (maxPrice) query.price.$lte = Number(maxPrice);
    }

    if (minAge || maxAge) {
      query.age = {};
      if (minAge) query.age.$gte = String(Number(minAge));
      if (maxAge) query.age.$lte = String(Number(maxAge));
    }

    if (minWeight || maxWeight) {
      query.weight = {};
      if (minWeight) query.weight.$gte = String(Number(minWeight));
      if (maxWeight) query.weight.$lte = String(Number(maxWeight));
    }

    if (search) {
      const searchTerms = search.trim().split(/\s+/).filter(t => t.length > 0);
      
      const charMap = {
        'c': '[cçCÇ]', 'ç': '[cçCÇ]', 'C': '[cçCÇ]', 'Ç': '[cçCÇ]',
        'g': '[gğGĞ]', 'ğ': '[gğGĞ]', 'G': '[gğGĞ]', 'Ğ': '[gğGĞ]',
        'i': '[iıİI]', 'ı': '[iıİI]', 'İ': '[iıİI]', 'I': '[iıİI]',
        'o': '[oöOÖ]', 'ö': '[oöOÖ]', 'O': '[oöOÖ]', 'Ö': '[oöOÖ]',
        's': '[sşSŞ]', 'ş': '[sşSŞ]', 'S': '[sşSŞ]', 'Ş': '[sşSŞ]',
        'u': '[uüUÜ]', 'ü': '[uüUÜ]', 'U': '[uüUÜ]', 'Ü': '[uüUÜ]',
      };

      const searchConditions = searchTerms.map(term => {
        const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        let regexStr = '';
        for (let char of escaped) {
          regexStr += charMap[char] || char;
        }
        const regex = { $regex: regexStr, $options: 'i' };
        
        return {
          $or: [
            { title: regex },
            { description: regex },
            { category: regex },
            { animalType: regex },
            { breed: regex }
          ]
        };
      });

      if (searchConditions.length > 0) {
        if (query.$and) {
          query.$and.push(...searchConditions);
        } else {
          query.$and = searchConditions;
        }
      }
    }

    let sortOptions = { createdAt: -1 };
    if (sort === 'price_asc') sortOptions = { price: 1, createdAt: -1 };
    else if (sort === 'price_desc') sortOptions = { price: -1, createdAt: -1 };
    else if (sort === 'oldest') sortOptions = { createdAt: 1 };

    const [listings, totalCount] = await Promise.all([
      Listing.find(query)
        .populate('user', 'name phone location avatar')
        .populate('favoriteCount')
        .sort(sortOptions)
        .skip(skip)
        .limit(limitNum)
        .lean(),
      Listing.countDocuments(query)
    ]);

    const totalPages = Math.ceil(totalCount / limitNum);
    const hasMore    = pageNum < totalPages;

    res.json({ listings, totalCount, page: pageNum, totalPages, hasMore });
  } catch (error) {
    res.status(500).json({ message: 'İlanlar getirilemedi', error: error.message });
  }
});

// Tek ilan detayı
router.get('/:id', async (req, res) => {
  try {
    const listing = await Listing.findById(req.params.id)
      .populate('user', 'name phone location email avatar')
      .populate('favoriteCount')
      .lean();
    
    if (!listing) {
      return res.status(404).json({ message: 'İlan bulunamadı' });
    }

    const oldViews = listing.views || 0;
    const newViews = oldViews + 1;

    // Görüntüleme sayısını artır
    await Listing.findByIdAndUpdate(req.params.id, { $inc: { views: 1 } });

    // 500'ün katlarında bildirim oluştur
    const milestones = [500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000];
    const crossedMilestone = milestones.find(m => oldViews < m && newViews >= m);

    if (crossedMilestone) {
      try {
        await Notification.create({
          user: listing.user._id || listing.user,
          type: 'view_milestone',
          title: 'Tebrikler! 🎉',
          message: `"${listing.title}" adlı ilanınız ${crossedMilestone}. kez görüntülendi!`,
          listing: listing._id
        });

        // Socket ile bildirim gönder
        const io = req.app.get('io');
        const userSockets = req.app.get('userSockets');
        if (io && userSockets) {
          const userId = String(listing.user._id || listing.user);
          const socketId = userSockets.get(userId);
          if (socketId && io.sockets.sockets.has(socketId)) {
            io.to(socketId).emit('new_notification', {
              type: 'view_milestone',
              title: 'Tebrikler! 🎉',
              message: `"${listing.title}" adlı ilanınız ${crossedMilestone}. kez görüntülendi!`
            });
          }
        }
      } catch (notifError) {
        console.error('Bildirim oluşturma hatası:', notifError);
      }
    }

    listing.views = newViews;
    res.json(listing);
  } catch (error) {
    res.status(500).json({ message: 'İlan getirilemedi', error: error.message });
  }
});

// Yeni ilan oluştur
router.post('/', auth, upload.array('images', 5), async (req, res) => {
  try {
    let images = [];
    if (req.files && req.files.length > 0) {
      const uploadPromises = req.files.map(async (file) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const filename = file.fieldname + '-' + uniqueSuffix + '.webp';
        const outputPath = path.join(uploadDir, filename);
        
        await sharp(file.buffer)
          .rotate() // EXIF orientation'a göre otomatik döndür
          .webp({ quality: 90 })
          .toFile(outputPath);
          
        return 'ilanlar/' + filename;
      });
      images = await Promise.all(uploadPromises);
    }
    
    // Yassı gelen form datasından lokasyon nesnesi oluşturuluyor
    const bodyData = { ...req.body };
    if (bodyData.city || bodyData.district) {
      bodyData.location = {
        city: bodyData.city || 'Belirtilmemiş',
        district: bodyData.district || 'Belirtilmemiş'
      };
      delete bodyData.city;
      delete bodyData.district;
    }
    
    const listing = new Listing({
      ...bodyData,
      user: req.userId,
      images
    });
    
    await listing.save();

    // İlan yayınlandı bildirimi oluştur
    try {
      await Notification.create({
        user: req.userId,
        type: 'listing_published',
        title: 'İlan Yayınlandı ✅',
        message: `"${listing.title}" adlı ilanınız başarıyla yayınlanmıştır.`,
        listing: listing._id
      });

      // Socket ile bildirim gönder
      const io = req.app.get('io');
      const userSockets = req.app.get('userSockets');
      if (io && userSockets) {
        const socketId = userSockets.get(String(req.userId));
        if (socketId && io.sockets.sockets.has(socketId)) {
          io.to(socketId).emit('new_notification', {
            type: 'listing_published',
            title: 'İlan Yayınlandı ✅',
            message: `"${listing.title}" adlı ilanınız başarıyla yayınlanmıştır.`
          });
        }
      }
    } catch (notifError) {
      // Silent error
    }

    res.status(201).json(listing);
  } catch (error) {
    res.status(500).json({ message: 'İlan oluşturulamadı', error: error.message });
  }
});

// İlan güncelle
router.put('/:id', auth, upload.array('newImages', 5), async (req, res) => {
  try {
    const listing = await Listing.findOne({ _id: req.params.id, user: req.userId });
    
    if (!listing) {
      return res.status(404).json({ message: 'İlan bulunamadı veya yetkiniz yok' });
    }

    // Yeni resimleri işle
    let newImages = [];
    if (req.files && req.files.length > 0) {
      const uploadPromises = req.files.map(async (file) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const filename = file.fieldname + '-' + uniqueSuffix + '.webp';
        const outputPath = path.join(uploadDir, filename);
        
        await sharp(file.buffer)
          .rotate() // EXIF orientation'a göre otomatik döndür
          .webp({ quality: 90 })
          .toFile(outputPath);
          
        return 'ilanlar/' + filename;
      });
      newImages = await Promise.all(uploadPromises);
    }

    // Silinecek resimleri tespit et ve sunucudan sil
    let currentImages = [...(listing.images || [])];
    if (req.body.deletedImages) {
      let deletedImages = req.body.deletedImages;
      if (typeof deletedImages === 'string') {
        deletedImages = deletedImages.split(',').map(s => s.trim());
      } else if (!Array.isArray(deletedImages)) {
        deletedImages = [deletedImages];
      }

      deletedImages.forEach(image => {
        const index = currentImages.indexOf(image);
        if (index > -1) {
          currentImages.splice(index, 1);
          // Diskten sil
          const imagePath = path.join(__dirname, '../uploads', image);
          if (fs.existsSync(imagePath)) {
            try {
              fs.unlinkSync(imagePath);
            } catch (err) {
              // Silent error
            }
          }
        }
      });
    }

    const finalImages = [...currentImages, ...newImages];
    
    // Yassı gelen form datasından lokasyon nesnesi oluşturuluyor
    const bodyData = { ...req.body };
    if (bodyData.city || bodyData.district) {
      bodyData.location = {
        city: bodyData.city || listing.location?.city || 'Belirtilmemiş',
        district: bodyData.district || listing.location?.district || 'Belirtilmemiş'
      };
      delete bodyData.city;
      delete bodyData.district;
    }
    delete bodyData.deletedImages;

    Object.assign(listing, bodyData, { images: finalImages, updatedAt: Date.now() });
    await listing.save();
    
    res.json(listing);
  } catch (error) {
    res.status(500).json({ message: 'İlan güncellenemedi', error: error.message });
  }
});

// İlan sil
router.delete('/:id', auth, async (req, res) => {
  try {
    const listing = await Listing.findOneAndDelete({ _id: req.params.id, user: req.userId });
    
    if (!listing) {
      return res.status(404).json({ message: 'İlan bulunamadı veya yetkiniz yok' });
    }

    // Kullanıcıların favorilerinden bu ilanı kaldır
    await User.updateMany(
      { favorites: req.params.id },
      { $pull: { favorites: req.params.id } }
    );

    // Bu ilana ait olan bildirimleri tamamen sil
    await Notification.deleteMany({ listing: req.params.id });

    // İlana ait resimleri sunucudan sil
    if (listing.images && listing.images.length > 0) {
      listing.images.forEach(image => {
        const imagePath = path.join(__dirname, '../uploads', image);
        if (fs.existsSync(imagePath)) {
          try {
            fs.unlinkSync(imagePath);
          } catch (err) {
            // Silent error
          }
        }
      });
    }

    res.json({ message: 'İlan silindi' });
  } catch (error) {
    res.status(500).json({ message: 'İlan silinemedi', error: error.message });
  }
});

module.exports = router;
