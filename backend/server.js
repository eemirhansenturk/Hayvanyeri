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
  console.log('Socket connected:', socket.id);

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
    console.log(`Registered user ${userId} on socket ${socket.id}`);
    console.log('Active users:', Array.from(userSockets.keys()));

    try {
      await markIncomingMessagesDeliveredAndNotify(userId);
    } catch (error) {
      console.error('Register delivered sync error:', error);
    }
  });

  socket.on('disconnect', () => {
    console.log('Socket disconnected:', socket.id);
    for (const [userId, socketId] of userSockets.entries()) {
      if (socketId === socket.id) {
        userSockets.delete(userId);
        console.log(`Removed user ${userId} from active map`);
        break;
      }
    }
    pruneStaleSocketMappings();
    console.log('Active users:', Array.from(userSockets.keys()));
  });
});

app.set('io', io);
app.set('userSockets', userSockets);

// Middleware
app.use(cors());
app.use(express.json());
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

mongoose.connect('mongodb://localhost:27017/hayvanyeri')
  .then(() => console.log('MongoDB baglantisi basarili'))
  .catch((err) => console.error('MongoDB baglanti hatasi:', err));

// Routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/listings', require('./routes/listings'));
app.use('/api/messages', require('./routes/messages'));
app.use('/api/users', require('./routes/users'));
app.use('/api/locations', require('./routes/locations'));
app.use('/api/support', require('./routes/support'));

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server ${PORT} portunda calisiyor`);
  console.log(`Yerel: http://localhost:${PORT}`);
});
