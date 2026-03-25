const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const Listing = require('../models/Listing');
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
      page, limit
    } = req.query;

    const pageNum  = Math.max(1, parseInt(page)  || 1);
    const limitNum = Math.min(50, Math.max(1, parseInt(limit) || 10));
    const skip     = (pageNum - 1) * limitNum;
    
    let query = { status: 'aktif' };
    
    if (category) query.category = category;
    if (listingType) query.listingType = listingType;
    if (city) query['location.city'] = { $regex: city, $options: 'i' };
    if (district) query['location.district'] = { $regex: district, $options: 'i' };
    if (animalType) query.animalType = animalType;
    if (breed) query.breed = breed;
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
      query.$or = [
        { title: { $regex: search, $options: 'i' } },
        { description: { $regex: search, $options: 'i' } }
      ];
    }

    const [listings, totalCount] = await Promise.all([
      Listing.find(query)
        .populate('user', 'name phone location avatar')
        .sort({ createdAt: -1 })
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
    const listing = await Listing.findByIdAndUpdate(
      req.params.id,
      { $inc: { views: 1 } },
      { returnDocument: 'after' }
    )
      .populate('user', 'name phone location email avatar')
      .lean();
    
    if (!listing) {
      return res.status(404).json({ message: 'İlan bulunamadı' });
    }

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
              console.error('Silinirken hata:', err);
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

    // İlana ait resimleri sunucudan sil
    if (listing.images && listing.images.length > 0) {
      listing.images.forEach(image => {
        const imagePath = path.join(__dirname, '../uploads', image);
        if (fs.existsSync(imagePath)) {
          try {
            fs.unlinkSync(imagePath);
          } catch (err) {
            console.error('Resim silinirken hata oluştu:', err);
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
