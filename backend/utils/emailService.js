const nodemailer = require("nodemailer");

const transporter = nodemailer.createTransport({
  host: "smtp.gmail.com",
  port: 587,
  secure: false,
  auth: {
    user: "hayvanyeri@gmail.com",
    pass: "ubldwxtgcvnwmfkb",
  },
  tls: {
    rejectUnauthorized: false,
  },
});

const sendPasswordResetEmail = async (email, resetToken) => {
  // URL'i .env dosyasından alıyoruz, bulamazsa kendi fallback IP'mizi kullanıyoruz
  const baseUrl = process.env.FRONTEND_URL || 'http://192.168.1.7:3000';
  const resetUrl = `${baseUrl}/reset-password/${resetToken}`;

  const mailOptions = {
    from: '"Hayvanyeri" <hayvanyeri@gmail.com>',
    to: email,
    subject: "Şifre Sıfırlama - Hayvanyeri",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #2e7d32;">Şifre Sıfırlama Talebi</h2>
        <p>Merhaba,</p>
        <p>Hayvanyeri hesabınız için şifre sıfırlama talebinde bulundunuz.</p>
        <p>Şifrenizi sıfırlamak için aşağıdaki bağlantıya tıklayın:</p>
        <div style="text-align: center; margin: 30px 0;">
          <a href="${resetUrl}" style="display: inline-block; padding: 14px 28px; background-color: #2e7d32; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 16px;">Şifremi Sıfırla</a>
        </div>
        <p style="color: #666; font-size: 14px;">Veya bu bağlantıyı tarayıcınıza kopyalayın:</p>
        <p style="background: #f5f5f5; padding: 12px; border-radius: 4px; word-break: break-all; font-size: 13px;">${resetUrl}</p>
        <p style="color: #e65100; font-weight: bold; margin-top: 20px;">⏰ Bu bağlantı 1 saat geçerlidir.</p>
        <p style="color: #666; margin-top: 20px;">Eğer bu talebi siz yapmadıysanız, bu e-postayı görmezden gelebilirsiniz.</p>
        <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">
        <p style="color: #666; font-size: 12px; text-align: center;">Hayvanyeri Ekibi</p>
      </div>
    `,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    return { success: true };
  } catch (error) {
    return { success: false, error: error.message };
  }
};

const sendVerificationEmail = async (email, verificationCode) => {
  const mailOptions = {
    from: '"Hayvanyeri" <hayvanyeri@gmail.com>',
    to: email,
    subject: "Email Doğrulama Kodu - Hayvanyeri",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #2e7d32;">Email Doğrulama</h2>
        <p>Merhaba,</p>
        <p>Hayvanyeri'ne hoş geldiniz! Hesabınızı oluşturmak için aşağıdaki doğrulama kodunu kullanın:</p>
        <div style="text-align: center; margin: 30px 0;">
          <div style="display: inline-block; padding: 20px 40px; background-color: #f5f5f5; border-radius: 12px; border: 2px dashed #2e7d32;">
            <span style="font-size: 32px; font-weight: bold; color: #2e7d32; letter-spacing: 8px;">${verificationCode}</span>
          </div>
        </div>
        <p style="color: #e65100; font-weight: bold; margin-top: 20px;">⏰ Bu kod 3 dakika geçerlidir.</p>
        <p style="color: #666; margin-top: 20px;">Eğer bu talebi siz yapmadıysanız, bu e-postayı görmezden gelebilirsiniz.</p>
        <hr style="margin: 30px 0; border: none; border-top: 1px solid #ddd;">
        <p style="color: #666; font-size: 12px; text-align: center;">Hayvanyeri Ekibi</p>
      </div>
    `,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    return { success: true };
  } catch (error) {
    return { success: false, error: error.message };
  }
};

module.exports = { sendPasswordResetEmail, sendVerificationEmail };
