const mongoose = require('mongoose');

const supportRequestSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  name: { type: String, required: true },
  email: { type: String, required: true },
  category: { type: String, default: 'Genel' },
  subject: { type: String, required: true },
  message: { type: String, required: true },
  status: { type: String, default: 'open', enum: ['open', 'in_progress', 'closed'] },
  createdAt: { type: Date, default: Date.now, index: true },
  updatedAt: { type: Date, default: Date.now }
});

supportRequestSchema.pre('save', function() {
  this.updatedAt = new Date();
});

module.exports = mongoose.model('SupportRequest', supportRequestSchema);
