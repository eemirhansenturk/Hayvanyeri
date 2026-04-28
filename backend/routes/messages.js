const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Message = require('../models/Message');
const Notification = require('../models/Notification');
const Listing = require('../models/Listing');
const User = require('../models/User');
const auth = require('../middleware/auth');
const { sendPushNotification } = require('../utils/firebase');

function getActiveSocketId(req, userId) {
  const io = req.app.get('io');
  const userSockets = req.app.get('userSockets');
  if (!io || !userSockets || !userId) return null;

  const normalizedUserId = String(userId);
  const socketId = userSockets.get(normalizedUserId);
  if (!socketId) return null;

  if (!io.sockets.sockets.has(socketId)) {
    userSockets.delete(normalizedUserId);
    return null;
  }

  return socketId;
}

// Get unread count
router.get('/unread-count', auth, async (req, res) => {
  try {
    const count = await Message.countDocuments({
      receiver: req.userId,
      read: false,
      deletedBy: { $ne: req.userId }
    });

    res.json({ count });
  } catch (error) {
    res.status(500).json({ message: 'Sayi alinamadi' });
  }
});

// Mark all incoming messages as delivered
router.post('/mark-delivered', auth, async (req, res) => {
  try {
    const userId = req.userId;

    const undeliveredMessages = await Message.find({
      receiver: userId,
      delivered: false,
      deletedBy: { $ne: userId }
    }).select('sender listing').lean();

    if (undeliveredMessages.length > 0) {
      await Message.updateMany(
        { receiver: userId, delivered: false },
        { delivered: true }
      );

      const io = req.app.get('io');
      const userSockets = req.app.get('userSockets');

      if (io && userSockets) {
        const senderListingPairs = new Map();

        for (const msg of undeliveredMessages) {
          const senderId = msg.sender.toString();
          const listingId = msg.listing.toString();
          const key = `${senderId}-${listingId}`;

          if (!senderListingPairs.has(key)) {
            senderListingPairs.set(key, { senderId, listingId });
          }
        }

        for (const { senderId, listingId } of senderListingPairs.values()) {
          const senderSocketId = getActiveSocketId(req, senderId);

          if (senderSocketId) {
            io.to(senderSocketId).emit('messages_delivered', {
              receiverId: String(userId),
              listingId
            });
          }
        }
      }
    }

    res.json({ success: true, count: undeliveredMessages.length });
  } catch (error) {
    res.status(500).json({ message: 'Islem basarisiz' });
  }
});

// Get conversations
router.get('/conversations', auth, async (req, res) => {
  try {
    const userId = new mongoose.Types.ObjectId(req.userId);
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 20;
    const skip = (page - 1) * limit;

    const [aggregationResult] = await Message.aggregate([
      { $match: { $or: [{ sender: userId }, { receiver: userId }] } },
      { $match: { deletedBy: { $ne: userId } } },
      { $match: { listing: { $exists: true, $ne: null } } },
      {
        $addFields: {
          otherUser: {
            $cond: [{ $eq: ['$sender', userId] }, '$receiver', '$sender']
          }
        }
      },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: { listing: '$listing', otherUser: '$otherUser' },
          docId: { $first: '$_id' },
          latestCreatedAt: { $first: '$createdAt' },
          unreadCount: {
            $sum: {
              $cond: [
                {
                  $and: [
                    { $eq: ['$receiver', userId] },
                    { $eq: ['$read', false] }
                  ]
                },
                1,
                0
              ]
            }
          }
        }
      },
      {
        $facet: {
          paginated: [
            { $sort: { latestCreatedAt: -1 } },
            { $skip: skip },
            { $limit: limit },
            { $project: { _id: 0, docId: 1, unreadCount: 1 } }
          ],
          totalCount: [{ $count: 'count' }]
        }
      }
    ]);

    const paginatedIds = (aggregationResult?.paginated ?? []).map((item) => item.docId);
    const unreadCountMap = new Map(
      (aggregationResult?.paginated ?? []).map((item) => [String(item.docId), item.unreadCount || 0])
    );
    const total = aggregationResult?.totalCount?.[0]?.count ?? 0;

    let conversations = [];
    if (paginatedIds.length > 0) {
      conversations = await Message.find({ _id: { $in: paginatedIds } })
        .populate('sender', 'name avatar')
        .populate('receiver', 'name avatar')
        .populate('listing', 'title images status')
        .lean();

      const orderMap = new Map(paginatedIds.map((id, index) => [String(id), index]));
      conversations.sort(
        (a, b) => (orderMap.get(String(a._id)) ?? 0) - (orderMap.get(String(b._id)) ?? 0)
      );
      conversations = conversations.map((conversation) => ({
        ...conversation,
        unreadCount: unreadCountMap.get(String(conversation._id)) ?? 0
      }));
    }

    res.json({
      conversations,
      hasMore: skip + limit < total,
      total,
      page,
      limit
    });
  } catch (error) {
    res.status(500).json({ message: 'Konusmalar getirilemedi' });
  }
});

// Get messages for a listing + peer
router.get('/:listingId/:otherUserId', auth, async (req, res) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 10;

    const total = await Message.countDocuments({
      listing: req.params.listingId,
      deletedBy: { $ne: req.userId },
      $or: [
        { sender: req.userId, receiver: req.params.otherUserId },
        { sender: req.params.otherUserId, receiver: req.userId }
      ]
    });

    const skip = Math.max(0, total - (page * limit));
    const actualLimit = Math.min(limit, total - skip);

    const messages = await Message.find({
      listing: req.params.listingId,
      deletedBy: { $ne: req.userId },
      $or: [
        { sender: req.userId, receiver: req.params.otherUserId },
        { sender: req.params.otherUserId, receiver: req.userId }
      ]
    })
      .populate('sender', 'name avatar')
      .populate('receiver', 'name avatar')
      .sort({ createdAt: 1 })
      .skip(skip)
      .limit(actualLimit)
      .lean();

    const deliveredUpdate = await Message.updateMany(
      {
        listing: req.params.listingId,
        receiver: req.userId,
        sender: req.params.otherUserId,
        delivered: false
      },
      { delivered: true }
    );

    if (deliveredUpdate.modifiedCount > 0) {
      const io = req.app.get('io');
      const userSockets = req.app.get('userSockets');

        if (io && userSockets) {
        const senderSocketId = getActiveSocketId(req, req.params.otherUserId);

        if (senderSocketId) {
          io.to(senderSocketId).emit('messages_delivered', {
            receiverId: String(req.userId),
            listingId: String(req.params.listingId)
          });
        }
      }
    }

    const readUpdate = await Message.updateMany(
      {
        listing: req.params.listingId,
        receiver: req.userId,
        sender: req.params.otherUserId,
        read: false
      },
      { read: true, delivered: true }
    );

    if (readUpdate.modifiedCount > 0) {
      const io = req.app.get('io');
      const userSockets = req.app.get('userSockets');
      if (io && userSockets) {
        const senderSocketId = getActiveSocketId(req, req.params.otherUserId);
        if (senderSocketId) {
          io.to(senderSocketId).emit('messages_read', {
            listingId: String(req.params.listingId),
            readBy: String(req.userId)
          });
        }
      }
    }

    // İlan durumunu kontrol et
    const ListingModel = require('../models/Listing');
    const listingInfo = await ListingModel.findById(req.params.listingId).select('status title user').lean();
    const listingRemoved = !listingInfo || listingInfo.status === 'silindi';
    const listingPassive = listingInfo && listingInfo.status === 'pasif';

    res.json({
      messages,
      hasMore: skip > 0,
      total,
      page,
      limit,
      listingRemoved,
      listingPassive,
      listingTitle: listingInfo?.title ?? null,
      listingOwner: listingInfo?.user ? String(listingInfo.user) : null
    });
  } catch (error) {
    res.status(500).json({ message: 'Mesajlar getirilemedi' });
  }
});

// Send message
router.post('/', auth, async (req, res) => {
  try {
    const { listing, receiver, content } = req.body;

    // İlan silinmiş veya pasif mi kontrol et
    const listingDoc = await require('../models/Listing').findById(listing).select('status').lean();
    if (!listingDoc || listingDoc.status === 'silindi' || listingDoc.status === 'pasif') {
      return res.status(403).json({ message: 'Bu ilan kaldırıldığı veya pasif olduğu için mesaj gönderilemiyor' });
    }

    const message = new Message({
      listing,
      sender: req.userId,
      receiver,
      content,
      delivered: false
    });

    await message.save();
    await message.populate(['sender', 'receiver', 'listing'], 'name avatar title');

    const io = req.app.get('io');
    const userSockets = req.app.get('userSockets');

    if (io && userSockets) {
      const receiverSocketId = getActiveSocketId(req, receiver);

      if (receiverSocketId) {
        message.delivered = true;
        await message.save();

        io.to(receiverSocketId).emit('receive_message', {
          message: message.toObject(),
          listingId: listing,
          senderId: req.userId
        });

        io.to(receiverSocketId).emit('new_message_notification', {
          title: 'Yeni Mesaj',
          body: `${message.sender.name}: ${content}`,
          listingId: listing,
          senderId: req.userId,
          messageId: message._id
        });

        const senderSocketId = getActiveSocketId(req, req.userId);
        if (senderSocketId) {
          io.to(senderSocketId).emit('messages_delivered', {
            receiverId: String(receiver),
            listingId: String(listing)
          });
        }
      }
    }

    // Push notification gönder
    try {
      const receiverUser = await User.findById(receiver).select('fcmTokens').lean();
      if (receiverUser && receiverUser.fcmTokens && receiverUser.fcmTokens.length > 0) {
        const senderName = (message.sender && message.sender.name) ? message.sender.name : 'Bir kullanıcı';
        const listingTitle = (message.listing && message.listing.title) ? message.listing.title : 'İlan';
        sendPushNotification(
          receiverUser.fcmTokens,
          'Yeni Mesaj 💬',
          `${senderName} kullanıcısı "${listingTitle}" adlı ilanınız için size mesaj attı:\n${content}`,
          { 
            type: 'message', 
            listingId: String(listing),
            listingTitle: listingTitle,
            otherUserId: String(req.userId),
            otherUserName: senderName
          }
        );
      }
    } catch (pushErr) {
      console.error('Mesaj push gonderim hatasi:', pushErr);
    }

    // Mesaj bildirimi oluştur (ilan sahibine) - Sadece yanıt alınmamışsa
    try {
      const listingDoc = await Listing.findById(listing).lean();
      const senderUser = await User.findById(req.userId).lean();
      
      if (listingDoc && String(listingDoc.user) === String(receiver)) {
        // Son mesajları kontrol et - receiver'dan sender'a yanıt var mı?
        const lastMessages = await Message.find({
          listing: listing,
          $or: [
            { sender: req.userId, receiver: receiver },
            { sender: receiver, receiver: req.userId }
          ]
        })
        .sort({ createdAt: -1 })
        .limit(10)
        .lean();

        // Sender'ın son mesajından sonra receiver'dan yanıt gelmiş mi kontrol et
        let shouldCreateNotification = true;
        let foundCurrentSenderMessage = false;

        for (const msg of lastMessages) {
          const msgSender = String(msg.sender);
          const msgReceiver = String(msg.receiver);
          
          // Mevcut mesajı atla
          if (String(msg._id) === String(message._id)) {
            foundCurrentSenderMessage = true;
            continue;
          }

          // Eğer receiver'dan sender'a bir mesaj varsa, bildirim gönder
          if (msgSender === String(receiver) && msgReceiver === String(req.userId)) {
            shouldCreateNotification = true;
            break;
          }

          // Eğer sender'dan receiver'a daha önceki bir mesaj varsa ve araya receiver'dan yanıt girmemişse
          if (msgSender === String(req.userId) && msgReceiver === String(receiver)) {
            shouldCreateNotification = false;
            break;
          }
        }

        // Okunmamış mesaj bildirimi var mı kontrol et
        const existingNotification = await Notification.findOne({
          user: receiver,
          type: 'message',
          listing: listing,
          relatedUser: req.userId,
          read: false
        }).lean();

        // Eğer okunmamış bildirim varsa yeni bildirim oluşturma
        if (existingNotification) {
          shouldCreateNotification = false;
        }

        if (shouldCreateNotification) {
          await Notification.create({
            user: receiver,
            type: 'message',
            title: 'Yeni Mesaj 💬',
            message: `${senderUser.name} kullanıcısı "${listingDoc.title}" adlı ilanınız için size mesaj attı.`,
            listing: listing,
            relatedUser: req.userId
          });

          // Socket ile bildirim gönder
          if (io && userSockets) {
            const socketId = userSockets.get(String(receiver));
            if (socketId && io.sockets.sockets.has(socketId)) {
              io.to(socketId).emit('new_notification', {
                type: 'message',
                title: 'Yeni Mesaj 💬',
                message: `${senderUser.name} kullanıcısı "${listingDoc.title}" adlı ilanınız için size mesaj attı.`
              });
            }
          }
        }
      }
    } catch (notifError) {
      // Silent error
    }

    res.status(201).json(message);
  } catch (error) {
    res.status(500).json({ message: 'Mesaj gonderilemedi' });
  }
});

// Mark messages as read
router.put('/read/:listingId/:otherUserId', auth, async (req, res) => {
  try {
    const result = await Message.updateMany(
      {
        listing: req.params.listingId,
        receiver: req.userId,
        sender: req.params.otherUserId,
        read: false
      },
      { read: true, delivered: true }
    );

    const io = req.app.get('io');
    const userSockets = req.app.get('userSockets');

    if (io && userSockets) {
      const senderSocketId = getActiveSocketId(req, req.params.otherUserId);

      if (senderSocketId) {
        io.to(senderSocketId).emit('messages_read', {
          listingId: String(req.params.listingId),
          readBy: String(req.userId)
        });
      }
    }

    res.json({ success: true, count: result.modifiedCount });
  } catch (error) {
    res.status(500).json({ message: 'Islem basarisiz' });
  }
});

// Delete all messages with a user (soft delete for the current user)
router.delete('/user/:otherUserId', auth, async (req, res) => {
  try {
    const userId = req.userId;
    const otherUserId = req.params.otherUserId;

    await Message.updateMany(
      {
        $or: [
          { sender: userId, receiver: otherUserId },
          { sender: otherUserId, receiver: userId }
        ]
      },
      { $addToSet: { deletedBy: userId } }
    );

    res.json({ success: true, message: 'Kullanıcıyla olan tüm konuşmalar silindi' });
  } catch (error) {
    res.status(500).json({ message: 'Konuşmalar silinemedi' });
  }
});

// Delete conversation with a user for a specific listing (soft delete for current user)
router.delete('/listing/:listingId/user/:otherUserId', auth, async (req, res) => {
  try {
    const userId = req.userId;
    const listingId = req.params.listingId;
    const otherUserId = req.params.otherUserId;

    await Message.updateMany(
      {
        listing: listingId,
        $or: [
          { sender: userId, receiver: otherUserId },
          { sender: otherUserId, receiver: userId }
        ]
      },
      { $addToSet: { deletedBy: userId } }
    );

    res.json({ success: true, message: 'İlanla ilgili konuşma silindi' });
  } catch (error) {
    res.status(500).json({ message: 'Konuşmalar silinemedi' });
  }
});

module.exports = router;
