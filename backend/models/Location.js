const mongoose = require('mongoose');

const districtSchema = new mongoose.Schema({
  name: { type: String, required: true },
});

const locationSchema = new mongoose.Schema({
  city_name: { type: String, required: true },
  city_tkgm_id: { type: String, required: true, unique: true },
  districts: [districtSchema],
});

module.exports = mongoose.model('Location', locationSchema);
