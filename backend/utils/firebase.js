const admin = require('firebase-admin');
const path = require('path');

try {
  const serviceAccount = require(path.join(__dirname, '../serviceAccountKey.json'));

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  
  console.log('Firebase Admin SDK basariyla baslatildi.');
} catch (error) {
  console.error('Firebase Admin SDK baslatilamadi (serviceAccountKey.json bulunamamis olabilir):', error);
}

/**
 * Kullanicilara Push Notification gonderir
 * @param {Array<String>} tokens - Alici FCM token listesi
 * @param {String} title - Bildirim basligi
 * @param {String} body - Bildirim icerigi
 * @param {Object} data - Bildirime eklenecek gizli data payload'u
 */
const sendPushNotification = async (tokens, title, body, data = {}) => {
  if (!tokens || tokens.length === 0) return;

  const message = {
    notification: {
      title,
      body,
    },
    android: {
      notification: {
        channelId: 'high_importance_channel',
      },
    },
    data: {
      ...data,
      click_action: 'FLUTTER_NOTIFICATION_CLICK'
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    
    // Başarısız tokenları temizle
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(tokens[idx]);
        }
      });
      // Sessizce başarısız tokenları döndür (veritabanından silinebilir)
      return { successCount: response.successCount, failedTokens };
    }
    return { successCount: response.successCount, failedTokens: [] };
  } catch (error) {
    console.error('Push notification gonderim hatasi:', error);
  }
};

module.exports = {
  admin,
  sendPushNotification
};
