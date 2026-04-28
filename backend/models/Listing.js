const mongoose = require('mongoose');

const listingSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  title: { type: String, required: true },
  description: { type: String, required: true },
  category: { 
    type: String, 
    enum: ['büyükbaş', 'küçükbaş', 'kanatlı', 'evcil', 'diğer'],
    required: true 
  },
  animalType: { type: String, required: true },
  listingType: { 
    type: String, 
    enum: ['satılık', 'sahiplendirme'],
    required: true 
  },
  price: { type: Number, default: 0 },
  age: String,
  gender: { type: String, enum: ['erkek', 'dişi'] },
  breed: String,
  weight: String,
  healthStatus: String,
  vaccinated: { type: Boolean, default: false },
  vaccines: String, // Aşı listesi
  location: {
    city: { type: String, required: true },
    district: { type: String, required: true }
  },
  images: [String],
  status: { 
    type: String, 
    enum: ['aktif', 'satıldı', 'pasif', 'silindi'],
    default: 'aktif'
  },
  views: { type: Number, default: 0 },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});

listingSchema.index({ status: 1, createdAt: -1 });
listingSchema.index({ category: 1, status: 1 });
listingSchema.index({ listingType: 1, status: 1 });
listingSchema.index({ 'location.city': 1, status: 1 });
listingSchema.index({ user: 1, createdAt: -1 });

// Virtual field for favorite count
listingSchema.virtual('favoriteCount', {
  ref: 'User',
  localField: '_id',
  foreignField: 'favorites',
  count: true
});

// Ensure virtuals are included in JSON
listingSchema.set('toJSON', { virtuals: true });
listingSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Listing', listingSchema);
