const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const User = require('../models/User');

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
    res.status(500).json({ message: 'Giriş başarısız', error: error.message });
  }
});

module.exports = router;
