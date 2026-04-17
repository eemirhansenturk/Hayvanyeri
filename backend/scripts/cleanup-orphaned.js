/**
 * Sahipsiz (orphaned) ilanları temizleme scripti
 * Kullanıcısı silinmiş olan ilanları ve resimlerini kaldırır.
 * Çalıştır: node scripts/cleanup-orphaned.js
 */

require('dotenv').config();
const mongoose = require('mongoose');
const path = require('path');
const fs = require('fs');
const Listing = require('../models/Listing');
const User = require('../models/User');

async function cleanup() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('✅ MongoDB bağlandı');

  // Tüm ilanları getir
  const allListings = await Listing.find({}).lean();
  console.log(`📋 Toplam ilan sayısı: ${allListings.length}`);

  // Tüm mevcut kullanıcı ID'lerini al
  const allUsers = await User.find({}, '_id').lean();
  const userIds = new Set(allUsers.map(u => u._id.toString()));
  console.log(`👤 Toplam kullanıcı sayısı: ${allUsers.length}`);

  // Sahipsiz ilanları bul
  const orphaned = allListings.filter(l => !userIds.has(l.user?.toString()));
  console.log(`🗑️  Sahipsiz ilan sayısı: ${orphaned.length}`);

  if (orphaned.length === 0) {
    console.log('Temizlenecek sahipsiz ilan yok.');
    await mongoose.disconnect();
    return;
  }

  let deletedImages = 0;
  let deletedListings = 0;

  for (const listing of orphaned) {
    // Resimleri diskten sil
    if (listing.images && listing.images.length > 0) {
      for (const image of listing.images) {
        const imgPath = path.join(__dirname, '../uploads', image);
        if (fs.existsSync(imgPath)) {
          try {
            fs.unlinkSync(imgPath);
            deletedImages++;
            console.log(`  🖼️  Silindi: ${image}`);
          } catch (e) {
            console.log(`  ⚠️  Silinemedi: ${image} - ${e.message}`);
          }
        }
      }
    }

    // İlanı DB'den sil
    await Listing.findByIdAndDelete(listing._id);
    deletedListings++;
    console.log(`  📄 İlan silindi: ${listing.title} (${listing._id})`);
  }

  console.log(`\n✅ Tamamlandı: ${deletedListings} ilan, ${deletedImages} resim silindi.`);
  await mongoose.disconnect();
}

cleanup().catch(err => {
  console.error('❌ Hata:', err);
  process.exit(1);
});
