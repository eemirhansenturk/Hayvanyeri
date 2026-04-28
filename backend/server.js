const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();
const http = require('http');
const { Server } = require('socket.io');
const Message = require('./models/Message');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

// userId -> socketId
const userSockets = new Map();

function pruneStaleSocketMappings() {
  for (const [userId, socketId] of userSockets.entries()) {
    if (!io.sockets.sockets.has(socketId)) {
      userSockets.delete(userId);
    }
  }
}

async function markIncomingMessagesDeliveredAndNotify(userId) {
  if (!userId) return;

  const receiverId = String(userId);
  const undelivered = await Message.find({
    receiver: receiverId,
    delivered: false
  }).select('sender listing').lean();

  if (undelivered.length === 0) return;

  await Message.updateMany(
    { receiver: receiverId, delivered: false },
    { delivered: true }
  );

  const senderListingPairs = new Map();
  for (const msg of undelivered) {
    const senderId = String(msg.sender);
    const listingId = String(msg.listing);
    const key = `${senderId}-${listingId}`;
    if (!senderListingPairs.has(key)) {
      senderListingPairs.set(key, { senderId, listingId });
    }
  }

  for (const { senderId, listingId } of senderListingPairs.values()) {
    const senderSocketId = userSockets.get(senderId);
    if (!senderSocketId) continue;

    if (!io.sockets.sockets.has(senderSocketId)) {
      userSockets.delete(senderId);
      continue;
    }

    io.to(senderSocketId).emit('messages_delivered', {
      receiverId,
      listingId
    });
  }
}

io.on('connection', (socket) => {
  socket.on('register', async (userId) => {
    if (!userId) return;

    pruneStaleSocketMappings();

    // If this socket was previously mapped to another user, clean it first.
    for (const [existingUserId, existingSocketId] of userSockets.entries()) {
      if (existingSocketId === socket.id && existingUserId !== userId) {
        userSockets.delete(existingUserId);
      }
    }

    userSockets.set(String(userId), socket.id);

    try {
      await markIncomingMessagesDeliveredAndNotify(userId);
    } catch (error) {
      // Silent error
    }
  });

  socket.on('disconnect', () => {
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        break;
      }
    }
    pruneStaleSocketMappings();
  });
});

app.set('io', io);
app.set('userSockets', userSockets);

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files
app.use(express.static('public'));

app.use('/uploads', express.static('uploads', {
  maxAge: '30d',
  immutable: true
}));

app.get('/api/health', (req, res) => {
  res.json({
    status: 'OK',
    message: 'Backend calisiyor',
    timestamp: new Date().toISOString()
  });
});

// Şifre sıfırlama sayfası
app.get('/reset-password/:token', (req, res) => {
  res.redirect(`/api/reset-password.html?token=${req.params.token}`);
});

mongoose.connect(process.env.MONGODB_URI)
  .then(() => {})
  .catch((err) => console.error('MongoDB baglanti hatasi:', err));

// Routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/listings', require('./routes/listings'));
app.use('/api/messages', require('./routes/messages'));
app.use('/api/users', require('./routes/users'));
app.use('/api/locations', require('./routes/locations'));
app.use('/api/support', require('./routes/support'));
app.use('/api/notifications', require('./routes/notifications'));

// Deep Linking Verification Routes (Android & iOS)
app.get('/api/.well-known/assetlinks.json', (req, res) => {
  res.json([{
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.qparkai.hayvanyeri",
      "sha256_cert_fingerprints": [
        "AE:25:51:FB:51:F6:D1:E6:37:31:CF:DB:52:CB:3F:71:1C:47:D0:D0:25:4C:04:67:13:52:AA:16:3D:0B:03:5D"
      ]
    }
  }]);
});

app.get('/api/.well-known/apple-app-site-association', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.send(JSON.stringify({
    "applinks": {
      "apps": [],
      "details": [
        {
          "appID": "359SBFFXD9.com.qparkai.hayvanyeri",
          "paths": ["/ilan/*"]
        }
      ]
    }
  }));
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server calisiyor: http://localhost:${PORT}`);
});
