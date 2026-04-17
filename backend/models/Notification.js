const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  type: { 
    type: String, 
    enum: ['favorite', 'message', 'view_milestone', 'listing_published'],
    required: true 
  },
  title: { type: String, required: true },
  message: { type: String, required: true },
  listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing' },
  relatedUser: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  read: { type: Boolean, default: false },
  createdAt: { type: Date, default: Date.now, index: true }
});

notificationSchema.index({ user: 1, read: 1, createdAt: -1 });
notificationSchema.index({ user: 1, createdAt: -1 });

module.exports = mongoose.model('Notification', notificationSchema);
