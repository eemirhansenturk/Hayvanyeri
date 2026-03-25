const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const User = require('../models/User');
const SupportRequest = require('../models/SupportRequest');

router.post('/', auth, async (req, res) => {
  try {
    const { category, subject, message } = req.body;
    if (!subject || !message) {
      return res.status(400).json({ message: 'Konu ve mesaj zorunludur' });
    }

    const user = await User.findById(req.userId).select('name email').lean();
    if (!user) {
      return res.status(404).json({ message: 'Kullanici bulunamadi' });
    }

    const supportRequest = new SupportRequest({
      user: req.userId,
      name: user.name,
      email: user.email,
      category: category || 'Genel',
      subject: String(subject).trim(),
      message: String(message).trim(),
    });

    await supportRequest.save();
    res.status(201).json({ success: true, id: supportRequest._id });
  } catch (error) {
    res.status(500).json({ message: 'Destek talebi olusturulamadi', error: error.message });
  }
});

module.exports = router;
