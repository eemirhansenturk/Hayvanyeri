const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  phone: { type: String, required: true },
  location: {
    city: String,
    district: String
  },
  avatar: String,
  favorites: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Listing' }],
  resetPasswordToken: String,
  resetPasswordExpires: Date,
  verificationCode: String,
  verificationCodeExpires: Date,
  fcmTokens: [{ type: String }],
  createdAt: { type: Date, default: Date.now }
});

userSchema.pre('save', async function() {
  if (this.isModified('password')) {
    this.password = await bcrypt.hash(this.password, 10);
  }
});

userSchema.methods.comparePassword = async function(password) {
  return await bcrypt.compare(password, this.password);
};

module.exports = mongoose.model('User', userSchema);
