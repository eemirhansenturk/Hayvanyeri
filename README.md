# Hayvan Yeri - Hayvan Alım-Satım ve Sahiplendirme Platformu

Çiftçiler ve hayvan sahipleri için geliştirilmiş modern bir mobil uygulama. Hayvanlarınızı satabilir veya sahiplendirebilirsiniz.

## Özellikler

- 🐄 Büyükbaş, küçükbaş, kanatlı hayvan ilanları
- 💰 Satılık ve sahiplendirme ilanları
- 📸 Çoklu resim yükleme
- 💬 Satıcı-alıcı mesajlaşma sistemi
- 🔍 Kategori ve konum bazlı filtreleme
- 👤 Kullanıcı profil yönetimi
- 📱 Modern ve kullanıcı dostu arayüz

## Teknolojiler

### Backend
- Node.js & Express.js
- MongoDB
- JWT Authentication
- Multer (Resim yükleme)

### Mobile
- Flutter
- Provider (State management)
- HTTP
- Image Picker

## Kurulum

### Backend

```bash
cd hayvanyeri/backend
npm install
npm start
```

Backend http://localhost:3000 adresinde çalışacaktır.

### Mobile

```bash
cd hayvanyeri/mobile
flutter pub get
flutter run
```

## API Endpoints

### Auth
- POST `/api/auth/register` - Kayıt ol
- POST `/api/auth/login` - Giriş yap

### Listings
- GET `/api/listings` - Tüm ilanları getir
- GET `/api/listings/:id` - İlan detayı
- POST `/api/listings` - Yeni ilan oluştur (Auth gerekli)
- PUT `/api/listings/:id` - İlan güncelle (Auth gerekli)
- DELETE `/api/listings/:id` - İlan sil (Auth gerekli)

### Messages
- GET `/api/messages/:listingId/:otherUserId` - Mesajları getir (Auth gerekli)
- POST `/api/messages` - Mesaj gönder (Auth gerekli)

### Users
- GET `/api/users/profile` - Profil bilgisi (Auth gerekli)
- GET `/api/users/my-listings` - Kullanıcının ilanları (Auth gerekli)

## Veritabanı

MongoDB bağlantısı: `mongodb://localhost:27017/hayvanyeri`

## Ekran Görüntüleri

- Ana Sayfa: Grid layout ile ilan listesi
- İlan Detay: Resim galerisi, detaylı bilgiler, satıcı bilgileri
- İlan Oluştur: Form ile yeni ilan ekleme
- Mesajlaşma: Gerçek zamanlı mesajlaşma
- Profil: Kullanıcı bilgileri ve ilanları

## Lisans

MIT
