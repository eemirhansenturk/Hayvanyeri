class AppConstants {
  // Kategoriler ve hayvan türleri
  static const Map<String, List<String>> categoryAnimals = {
    'büyükbaş': ['İnek', 'Manda', 'At', 'Eşek', 'Katır', 'Deve'],
    'küçükbaş': ['Koyun', 'Keçi', 'Kuzu', 'Oğlak'],
    'kanatlı': ['Tavuk', 'Horoz', 'Ördek', 'Kaz', 'Hindi', 'Güvercin', 'Bıldırcın'],
    'evcil': ['Köpek', 'Kedi', 'Tavşan', 'Kuş', 'Balık', 'Sürüngen', 'Diğer'],
    'diğer': ['Arı', 'Sincap', 'Fare', 'Diğer'],
  };

  // Irklar (kategori bazlı)
  static const Map<String, List<String>> breeds = {
    'İnek': [
      'Simental',
      'Holştayn',
      'Montofon',
      'Jersey',
      'Angus',
      'Hereford',
      'Yerli Kara',
      'Boz Irk',
      'Doğu Anadolu Kırmızısı',
      'Güney Anadolu Kırmızısı',
      'Melez',
      'Diğer'
    ],
    'Koyun': [
      'Merinos',
      'Akkaraman',
      'İvesi',
      'Morkaraman',
      'Kıvırcık',
      'Karayaka',
      'Dağlıç',
      'Sakız',
      'Hemşin',
      'Norduz',
      'Melez',
      'Diğer'
    ],
    'Keçi': [
      'Kıl Keçisi',
      'Tiftik Keçisi (Ankara)',
      'Kilis Keçisi',
      'Malta Keçisi',
      'Saanen',
      'Alpin',
      'Melez',
      'Diğer'
    ],
    'Köpek': [
      'Kangal',
      'Akbaş',
      'Malaklı',
      'Kars Çoban Köpeği',
      'Sivas Kangalı',
      'Golden Retriever',
      'Labrador',
      'German Shepherd',
      'Melez',
      'Diğer'
    ],
    'Kedi': [
      'Tekir',
      'Sarman',
      'Siyam',
      'Van Kedisi',
      'Ankara Kedisi',
      'Scottish Fold',
      'British Shorthair',
      'Melez',
      'Diğer'
    ],
    'At': [
      'Arap Atı',
      'Safkan İngiliz',
      'Türk Atı',
      'Rahvan',
      'Hucul',
      'Melez',
      'Diğer'
    ],
    'Tavuk': [
      'Leghorn',
      'Rhode Island',
      'Sussex',
      'Brahma',
      'Yerli Tavuk',
      'Melez',
      'Diğer'
    ],
  };

  // Aşılar
  static const List<String> vaccines = [
    'Şap Aşısı',
    'Brusella Aşısı',
    'Şarbon Aşısı',
    'Kuduz Aşısı',
    'IBR Aşısı',
    'BVD Aşısı',
    'Enterotoksemi Aşısı',
    'Pastörella Aşısı',
    'Newcastle Aşısı',
    'Gumboro Aşısı',
    'Marek Aşısı',
    'Karma Aşı',
    'Diğer',
  ];

  // Türkiye şehirleri
  static const List<String> cities = [
    'Adana',
    'Adıyaman',
    'Afyonkarahisar',
    'Ağrı',
    'Aksaray',
    'Amasya',
    'Ankara',
    'Antalya',
    'Ardahan',
    'Artvin',
    'Aydın',
    'Balıkesir',
    'Bartın',
    'Batman',
    'Bayburt',
    'Bilecik',
    'Bingöl',
    'Bitlis',
    'Bolu',
    'Burdur',
    'Bursa',
    'Çanakkale',
    'Çankırı',
    'Çorum',
    'Denizli',
    'Diyarbakır',
    'Düzce',
    'Edirne',
    'Elazığ',
    'Erzincan',
    'Erzurum',
    'Eskişehir',
    'Gaziantep',
    'Giresun',
    'Gümüşhane',
    'Hakkari',
    'Hatay',
    'Iğdır',
    'Isparta',
    'İstanbul',
    'İzmir',
    'Kahramanmaraş',
    'Karabük',
    'Karaman',
    'Kars',
    'Kastamonu',
    'Kayseri',
    'Kırıkkale',
    'Kırklareli',
    'Kırşehir',
    'Kilis',
    'Kocaeli',
    'Konya',
    'Kütahya',
    'Malatya',
    'Manisa',
    'Mardin',
    'Mersin',
    'Muğla',
    'Muş',
    'Nevşehir',
    'Niğde',
    'Ordu',
    'Osmaniye',
    'Rize',
    'Sakarya',
    'Samsun',
    'Siirt',
    'Sinop',
    'Sivas',
    'Şanlıurfa',
    'Şırnak',
    'Tekirdağ',
    'Tokat',
    'Trabzon',
    'Tunceli',
    'Uşak',
    'Van',
    'Yalova',
    'Yozgat',
    'Zonguldak',
  ];

  // Yardımcı fonksiyonlar
  static List<String> getAnimalsForCategory(String category) {
    return categoryAnimals[category] ?? [];
  }

  static List<String> getBreedsForAnimal(String animal) {
    return breeds[animal] ?? ['Belirtilmemiş'];
  }
}
