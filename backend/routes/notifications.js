const express = require('express');
const router = express.Router();
const Notification = require('../models/Notification');
const auth = require('../middleware/auth');

// Bildirimleri getir (sayfalama destekli)
router.get('/', auth, async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip = (page - 1) * limit;

    const [notifications, totalCount, unreadCount] = await Promise.all([
      Notification.find({ user: req.userId })
        .populate('listing', 'title images')
        .populate('relatedUser', 'name avatar _id')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      Notification.countDocuments({ user: req.userId }),
      Notification.countDocuments({ user: req.userId, read: false })
    ]);

    const totalPages = Math.ceil(totalCount / limit);
    res.json({ 
      notifications, 
      totalCount, 
      unreadCount,
      page, 
      totalPages, 
      hasMore: page < totalPages 
    });
  } catch (error) {
    res.status(500).json({ message: 'Bildirimler getirilemedi', error: error.message });
  }
});

// Okunmamış bildirim sayısı
router.get('/unread-count', auth, async (req, res) => {
  try {
    const count = await Notification.countDocuments({ 
      user: req.userId, 
      read: false 
    });
    res.json({ count });
  } catch (error) {
    res.status(500).json({ message: 'Sayı alınamadı', error: error.message });
  }
});

// Bildirimi okundu olarak işaretle
router.put('/:id/read', auth, async (req, res) => {
  try {
    const notification = await Notification.findOneAndUpdate(
      { _id: req.params.id, user: req.userId },
      { read: true },
      { new: true }
    );
    
    if (!notification) {
      return res.status(404).json({ message: 'Bildirim bulunamadı' });
    }
    
    res.json(notification);
  } catch (error) {
    res.status(500).json({ message: 'İşlem başarısız', error: error.message });
  }
});

// Tüm bildirimleri okundu olarak işaretle
router.put('/mark-all-read', auth, async (req, res) => {
  try {
    await Notification.updateMany(
      { user: req.userId, read: false },
      { read: true }
    );
    res.json({ message: 'Tüm bildirimler okundu olarak işaretlendi' });
  } catch (error) {
    res.status(500).json({ message: 'İşlem başarısız', error: error.message });
  }
});

// Bildirimi sil
router.delete('/:id', auth, async (req, res) => {
  try {
    const notification = await Notification.findOneAndDelete({
      _id: req.params.id,
      user: req.userId
    });
    
    if (!notification) {
      return res.status(404).json({ message: 'Bildirim bulunamadı' });
    }
    
    res.json({ message: 'Bildirim silindi' });
  } catch (error) {
    res.status(500).json({ message: 'İşlem başarısız', error: error.message });
  }
});

module.exports = router;
