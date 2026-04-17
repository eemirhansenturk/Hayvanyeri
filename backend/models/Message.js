const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true, index: true },
  sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  receiver: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  content: { type: String, required: true },
  read: { type: Boolean, default: false },
  delivered: { type: Boolean, default: false },
  deletedBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  createdAt: { type: Date, default: Date.now, index: true }
});

// Karmaşık sorgular için bileşik indeks
messageSchema.index({ listing: 1, sender: 1, receiver: 1 });
messageSchema.index({ sender: 1, receiver: 1 });
messageSchema.index({ sender: 1, createdAt: -1 });
messageSchema.index({ receiver: 1, createdAt: -1 });
messageSchema.index({ receiver: 1, read: 1, createdAt: -1 });
messageSchema.index({ receiver: 1, delivered: 1, createdAt: -1 });

module.exports = mongoose.model('Message', messageSchema);
