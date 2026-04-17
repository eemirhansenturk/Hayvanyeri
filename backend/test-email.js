const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: 'hayvanyeri@gmail.com',
    pass: 'ubldwxtgcvnwmfkb'
  },
  tls: {
    rejectUnauthorized: false
  }
});

async function testEmail() {
  try {
    console.log('Email bağlantısı test ediliyor...');
    
    const info = await transporter.sendMail({
      from: '"Hayvanyeri Test" <hayvanyeri@gmail.com>',
      to: 'hayvanyeri@gmail.com',
      subject: 'Test Email',
      text: 'Bu bir test emailidir.',
      html: '<b>Bu bir test emailidir.</b>'
    });

    console.log('✓ Email başarıyla gönderildi!');
    console.log('Message ID:', info.messageId);
  } catch (error) {
    console.error('✗ Email gönderme hatası:');
    console.error('Hata:', error.message);
    console.error('Detay:', error);
  }
}

testEmail();
