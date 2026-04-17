const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const User = require('../models/User');
const { sendPasswordResetEmail } = require('../utils/emailService');

// Kayıt
router.post('/register', async (req, res) => {
  try {
    const { name, email, password, phone } = req.body;
    
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(400).json({ message: 'Bu email zaten kullanılıyor' });
    }

    const user = new User({
      name,
      email,
      password,
      phone
    });
    
    await user.save();
    
    const token = jwt.sign({ userId: user._id }, process.env.JWT_SECRET);
    res.status(201).json({ 
      token, 
      user: { 
        _id: user._id, 
        name: user.name, 
        email: user.email,
        phone: user.phone,
        location: user.location,
        avatar: user.avatar || '',
        favorites: user.favorites || []
      } 
    });
  } catch (error) {
    res.status(500).json({ message: 'Kayıt başarısız', error: error.message });
  }
});

// Giriş
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ message: 'Email veya şifre hatalı' });
    }

    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Email veya şifre hatalı' });
    }

    const token = jwt.sign({ userId: user._id }, process.env.JWT_SECRET);
    res.json({ 
      token, 
      user: { 
        _id: user._id, 
        name: user.name, 
        email: user.email,
        phone: user.phone,
        location: user.location,
        avatar: user.avatar || '',
        favorites: user.favorites || []
      } 
    });
  } catch (error) {
    res.status(500).json({ message: 'Email veya şifre hatalı' });
  }
});

// Şifre sıfırlama talebi
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;
    
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ message: 'Bu email adresi ile kayıtlı kullanıcı bulunamadı' });
    }

    const resetToken = crypto.randomBytes(32).toString('hex');
    user.resetPasswordToken = resetToken;
    user.resetPasswordExpires = Date.now() + 3600000; // 1 saat
    await user.save();

    // Email işlemini arka planda asenkron olarak başlat ve kullanıcıyı bekletme
    sendPasswordResetEmail(user.email, resetToken)
      .then(result => {
        if (!result.success) {
          console.error(`Şifre sıfırlama maili gönderilemedi (${user.email}):`, result.error);
        }
      })
      .catch(error => {
        console.error('Beklenmeyen mail gönderme hatası:', error.message);
      });
    
    // UI tarafında hızlı yanıt vermek için hemen başarılı dönüyoruz
    res.json({ message: 'Şifre sıfırlama bağlantısını e-posta adresinize gönderdik. E-postanın size ulaşması birkaç dakika sürebilir.' });
  } catch (error) {
    res.status(500).json({ message: 'Bir hata oluştu. Lütfen tekrar deneyin' });
  }
});

// Şifre sıfırlama
router.post('/reset-password', async (req, res) => {
  try {
    const { token, newPassword } = req.body;
    
    const user = await User.findOne({
      resetPasswordToken: token,
      resetPasswordExpires: { $gt: Date.now() }
    });

    if (!user) {
      return res.status(400).json({ message: 'Geçersiz veya süresi dolmuş bağlantı' });
    }

    user.password = newPassword;
    user.resetPasswordToken = undefined;
    user.resetPasswordExpires = undefined;
    await user.save();

    res.json({ message: 'Şifreniz başarıyla güncellendi' });
  } catch (error) {
    res.status(500).json({ message: 'Şifre güncellenemedi. Lütfen tekrar deneyin' });
  }
});

// Hesap silme
const authMiddleware = require('../middleware/auth');
const Listing = require('../models/Listing');
const Message = require('../models/Message');
const Notification = require('../models/Notification');
const path = require('path');
const fs = require('fs');

router.delete('/delete-account', authMiddleware, async (req, res) => {
  try {
    const { password } = req.body;

    if (!password) {
      return res.status(400).json({ message: 'Şifre gereklidir' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ message: 'Kullanıcı bulunamadı' });
    }

    // Şifreyi doğrula
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Şifre hatalı. Lütfen tekrar deneyin.' });
    }

    // Kullanıcının tüm ilanlarını bul (resimleri diskten silmek için)
    const userListings = await Listing.find({ user: req.userId }).lean();

    // İlan resimlerini diskten sil
    for (const listing of userListings) {
      if (listing.images && listing.images.length > 0) {
        for (const image of listing.images) {
          const imagePath = path.join(__dirname, '../uploads', image);
          if (fs.existsSync(imagePath)) {
            try { fs.unlinkSync(imagePath); } catch (_) {}
          }
        }
      }
    }

    // Avatar resmini diskten sil
    if (user.avatar) {
      // avatar; "avatars/filename.webp" veya tam URL olabilir
      const avatarRelative = user.avatar.startsWith('http')
        ? user.avatar.replace(/^https?:\/\/[^/]+\/uploads\//, '')
        : user.avatar.replace(/^\/uploads\//, '');
      const avatarPath = path.join(__dirname, '../uploads', avatarRelative);
      if (fs.existsSync(avatarPath)) {
        try { fs.unlinkSync(avatarPath); } catch (_) {}
      }
    }

    // İlanları DB'den sil (doğru alan: 'user')
    await Listing.deleteMany({ user: req.userId });

    // Mesajları sil
    await Message.deleteMany({ $or: [{ sender: req.userId }, { receiver: req.userId }] });

    // Bildirimleri sil
    await Notification.deleteMany({ user: req.userId });

    // Diğer kullanıcıların favori listelerinden bu kullanıcının ilanlarını kaldır
    const listingIds = userListings.map(l => l._id);
    if (listingIds.length > 0) {
      await User.updateMany(
        { favorites: { $in: listingIds } },
        { $pull: { favorites: { $in: listingIds } } }
      );
    }

    // Kullanıcıyı sil
    await User.findByIdAndDelete(req.userId);

    res.json({ message: 'Hesabınız başarıyla silindi' });
  } catch (error) {
    console.error('Hesap silme hatası:', error);
    res.status(500).json({ message: 'Hesap silinemedi. Lütfen tekrar deneyin.' });
  }
});

module.exports = router;
