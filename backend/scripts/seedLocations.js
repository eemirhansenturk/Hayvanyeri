const mongoose = require('mongoose');
const Location = require('../models/Location');

async function seedLocations() {
  try {
    console.log('MongoDB bağlantısı kuruluyor...');
    await mongoose.connect('mongodb://localhost:27017/hayvanyeri');
    console.log('MongoDB bağlandı. Eski lokasyon verileri siliniyor...');
    
    await Location.deleteMany({});
    
    console.log('iller çekiliyor (api.turkiyeapi.com)...');
    const citiesResponse = await fetch('https://api.turkiyeapi.com/api/iller');
    const citiesJson = await citiesResponse.json();
    const citiesData = citiesJson.data;

    let index = 1;
    for (const city of citiesData) {
      const cityName = city.label;
      const tkgmId = city.tkgm_id;

      console.log(`[${index}/${citiesData.length}] ${cityName} ilçeleri çekiliyor... (${tkgmId})`);
      
      let districts = [];
      try {
        const districtsResponse = await fetch(`https://api.turkiyeapi.com/api/ilceler/${tkgmId}`);
        if(districtsResponse.ok) {
           const districtsJson = await districtsResponse.json();
           districts = districtsJson.data.map(d => ({ name: d.label }));
        } else {
           console.log(`Uyarı: ${cityName} ilçeleri çekilemedi (Status ${districtsResponse.status})`);
        }
      } catch (innerError) {
        console.log(`Uyarı: ${cityName} ilçeleri çekilirken hata oluştu:`, innerError.message);
      }

      await Location.create({
        city_name: cityName,
        city_tkgm_id: tkgmId,
        districts: districts
      });
      
      index++;
      // Sunucuyu çok hızlı isteklerle yormamak için çok ufak bir bekleme süresi eklenebilir. (Opsiyonel)
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    
    console.log('Tüm veriler başarıyla kaydedildi!');
    process.exit(0);

  } catch (error) {
    console.error('Veri aktarımı sırasında bir hata oluştu:', error);
    process.exit(1);
  }
}

seedLocations();
