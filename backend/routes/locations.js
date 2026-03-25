const express = require('express');
const router = express.Router();
const Location = require('../models/Location');

// Tüm illeri getir (sadece name ve tkgm_id)
router.get('/cities', async (req, res) => {
  try {
    const cities = await Location.find({}, 'city_name city_tkgm_id')
      .sort({ city_name: 1 });
    
    // Uygulama "label" olarak bekliyorsa veriyi aynı formata dönüştür
    const formattedCities = cities.map(city => ({
      label: city.city_name,
      tkgm_id: city.city_tkgm_id
    }));
      
    res.json({ success: true, data: formattedCities });
  } catch (error) {
    res.status(500).json({ success: false, message: 'İller getirilemedi', error: error.message });
  }
});

// Bir ilin ilçelerini tkgm_id'ye göre getir
router.get('/districts/:tkgmId', async (req, res) => {
  try {
    const location = await Location.findOne({ city_tkgm_id: req.params.tkgmId }, 'districts');
    
    if (!location) {
      return res.status(404).json({ success: false, message: 'İl bulunamadı' });
    }

    // Uygulama "label" olarak bekliyorsa dönüştür
    const formattedDistricts = location.districts
      .map(d => ({ label: d.name }))
      .sort((a, b) => a.label.localeCompare(b.label, 'tr-TR')); // Türkçe karakter sıralaması

    res.json({ success: true, data: formattedDistricts });
  } catch (error) {
    res.status(500).json({ success: false, message: 'İlçeler getirilemedi', error: error.message });
  }
});

module.exports = router;
