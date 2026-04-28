const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const User = require('../models/User');
const Listing = require('../models/Listing');
const Notification = require('../models/Notification');
const auth = require('../middleware/auth');
const { sendPushNotification } = require('../utils/firebase');

const avatarUploadDir = 'uploads/avatars/';
if (!fs.existsSync(avatarUploadDir)) {
  fs.mkdirSync(avatarUploadDir, { recursive: true });
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }
});

// Kullanıcı profilini getir
router.get('/profile', auth, async (req, res) => {
  try {
    const user = await User.findById(req.userId).select('-password').lean();
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: 'Profil getirilemedi', error: error.message });
  }
});

// Diğer kullanıcı profilini ve aktif ilanlarını getir
router.get('/:id/profile', auth, async (req, res) => {
  try {
    const userId = req.params.id;
    const user = await User.findById(userId).select('name email location avatar createdAt').lean();
    if (!user) {
      return res.status(404).json({ message: 'Kullanıcı bulunamadı' });
    }

    const activeListings = await Listing.find({ user: userId, status: 'aktif' })
      .sort({ createdAt: -1 })
      .lean();

    res.json({
      user,
      listings: activeListings
    });
  } catch (error) {
    res.status(500).json({ message: 'Kullanıcı verisi getirilemedi', error: error.message });
  }
});

// Profil bilgilerini ve avatarı güncelle
router.put('/profile', auth, upload.single('avatar'), async (req, res) => {
  try {
    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ message: 'Kullanıcı bulunamadı' });
    }

    const { name, phone, city, district } = req.body;

    if (name != null && String(name).trim().length > 0) {
      user.name = String(name).trim();
    }
    if (phone != null && String(phone).trim().length > 0) {
      user.phone = String(phone).trim();
    }

    const nextCity = city != null ? String(city).trim() : user.location?.city;
    const nextDistrict = district != null ? String(district).trim() : user.location?.district;
    user.location = {
      city: nextCity || 'Belirtilmemis',
      district: nextDistrict || 'Belirtilmemis'
    };

    if (req.body.removeAvatar === 'true' || req.body.removeAvatar === true) {
      const oldAvatar = user.avatar;
      user.avatar = '';
      if (oldAvatar && oldAvatar.startsWith('avatars/')) {
        const oldPath = path.join(__dirname, '../uploads', oldAvatar);
        if (fs.existsSync(oldPath)) {
          try {
            fs.unlinkSync(oldPath);
          } catch (_) {}
        }
      }
    } else if (req.file) {
      const filename = `avatar-${req.userId}-${Date.now()}.webp`;
      const outputPath = path.join(avatarUploadDir, filename);

      await sharp(req.file.buffer)
        .rotate() // EXIF orientation'a göre otomatik döndür
        .resize(900, 900, { fit: 'cover', position: 'center' })
        .webp({ quality: 85 })
        .toFile(outputPath);

      const oldAvatar = user.avatar;
      user.avatar = `avatars/${filename}`;

      if (oldAvatar && oldAvatar.startsWith('avatars/')) {
        const oldPath = path.join(__dirname, '../uploads', oldAvatar);
        if (fs.existsSync(oldPath)) {
          try {
            fs.unlinkSync(oldPath);
          } catch (_) {}
        }
      }
    }

    await user.save();

    const safeUser = await User.findById(req.userId).select('-password').lean();
    res.json(safeUser);
  } catch (error) {
    res.status(500).json({ message: 'Profil güncellenemedi', error: error.message });
  }
});

// Kullanıcının ilanlarını getir (sayfalama destekli)
router.get('/my-listings', auth, async (req, res) => {
  try {
    const pageNum = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limitNum = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 10));
    const skip = (pageNum - 1) * limitNum;

    const [listings, totalCount] = await Promise.all([
      Listing.find({ user: req.userId, status: { $ne: 'silindi' } })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limitNum)
        .lean(),
      Listing.countDocuments({ user: req.userId, status: { $ne: 'silindi' } })
    ]);

    const totalPages = Math.ceil(totalCount / limitNum);
    res.json({ listings, totalCount, page: pageNum, totalPages, hasMore: pageNum < totalPages });
  } catch (error) {
    res.status(500).json({ message: 'İlanlar getirilemedi', error: error.message });
  }
});

// Favoriye ekle/cikar (toggle)
router.post('/favorites/:listingId', auth, async (req, res) => {
  try {
    const user = await User.findById(req.userId);
    const listingId = req.params.listingId;
    const listing = await Listing.findById(listingId).lean();

    if (!listing) {
      return res.status(404).json({ message: 'İlan bulunamadı' });
    }

    const isFavorited = user.favorites.includes(listingId);

    if (isFavorited) {
      user.favorites.pull(listingId);
    } else {
      user.favorites.push(listingId);

      // Favoriye eklendi bildirimi oluştur (kendi ilanı değilse)
      if (String(listing.user) !== String(req.userId)) {
        try {
          await Notification.create({
            user: listing.user,
            type: 'favorite',
            title: 'Yeni Favori ❤️',
            message: `${user.name} kullanıcısı "${listing.title}" adlı ilanınızı favorilerine ekledi.`,
            listing: listingId,
            relatedUser: req.userId
          });

          // Socket ile bildirim gönder
          const io = req.app.get('io');
          const userSockets = req.app.get('userSockets');
          if (io && userSockets) {
            const socketId = userSockets.get(String(listing.user));
            if (socketId && io.sockets.sockets.has(socketId)) {
              io.to(socketId).emit('new_notification', {
                type: 'favorite',
                title: 'Yeni Favori ❤️',
                message: `${user.name} kullanıcısı "${listing.title}" adlı ilanınızı favorilerine ekledi.`
              });
            }
          }

          // Push notification gönder
          try {
            const listingOwner = await User.findById(listing.user).select('fcmTokens').lean();
            if (listingOwner && listingOwner.fcmTokens && listingOwner.fcmTokens.length > 0) {
              sendPushNotification(
                listingOwner.fcmTokens,
                'Yeni Favori ❤️',
                `${user.name} kullanıcısı "${listing.title}" adlı ilanınızı favorilerine ekledi.`,
                { type: 'favorite', listingId: String(listingId) }
              );
            }
          } catch (pushErr) {
            console.error('Favori push gonderim hatasi:', pushErr);
          }
        } catch (notifError) {
          // Silent error
        }
      }
    }

    await user.save();
    res.json({ message: isFavorited ? 'Favorilerden cikarildi' : 'Favorilere eklendi', isFavorited: !isFavorited });
  } catch (error) {
    res.status(500).json({ message: 'Islem basarisiz', error: error.message });
  }
});

// Favori ilanlari getir
router.get('/favorites', auth, async (req, res) => {
  try {
    const user = await User.findById(req.userId)
      .populate({
        path: 'favorites',
        populate: { path: 'user', select: 'name phone location' },
        options: { sort: { createdAt: -1 }, lean: true }
      })
      .lean();

    res.json(user.favorites || []);
  } catch (error) {
    res.status(500).json({ message: 'Favoriler getirilemedi', error: error.message });
  }
});

// Kullanıcı şifresini güncelle
router.put('/change-password', auth, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ message: 'Mevcut ve yeni şifre zorunludur' });
    }

    if (String(newPassword).length < 6) {
      return res.status(400).json({ message: 'Yeni şifre en az 6 karakter olmalı' });
    }

    if (String(currentPassword) === String(newPassword)) {
      return res.status(400).json({ message: 'Yeni şifre mevcut şifre ile aynı olamaz' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ message: 'Kullanıcı bulunamadı' });
    }

    const isMatch = await user.comparePassword(String(currentPassword));
    if (!isMatch) {
      return res.status(400).json({ message: 'Mevcut şifre hatalı' });
    }

    user.password = String(newPassword);
    await user.save();

    return res.json({ success: true, message: 'Şifre başarıyla güncellendi' });
  } catch (error) {
    return res.status(500).json({ message: 'Şifre güncellenemedi', error: error.message });
  }
});

// FCM Token Kaydetme
router.post('/fcm-token', auth, async (req, res) => {
  try {
    const { token } = req.body;
    if (!token) {
      return res.status(400).json({ message: 'Token zorunludur' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ message: 'Kullanıcı bulunamadı' });
    }

    if (!user.fcmTokens) {
      user.fcmTokens = [];
    }

    // Token zaten yoksa ekle (tekrarları önle)
    if (!user.fcmTokens.includes(token)) {
      user.fcmTokens.push(token);
      await user.save();
    }

    return res.json({ success: true, message: 'FCM Token kaydedildi' });
  } catch (error) {
    return res.status(500).json({ message: 'FCM Token kaydedilemedi', error: error.message });
  }
});

module.exports = router;
