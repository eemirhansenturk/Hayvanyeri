const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Message = require('../models/Message');
const auth = require('../middleware/auth');

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
      read: false
    });

    res.json({ count });
  } catch (error) {
    console.error('Unread count error:', error);
    res.status(500).json({ message: 'Sayi alinamadi', error: error.message });
  }
});

// Mark all incoming messages as delivered
router.post('/mark-delivered', auth, async (req, res) => {
  try {
    const userId = req.userId;

    const undeliveredMessages = await Message.find({
      receiver: userId,
      delivered: false
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
    console.error('Mark delivered error:', error);
    res.status(500).json({ message: 'Islem basarisiz', error: error.message });
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
        .populate('listing', 'title images')
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
    console.error('Conversations error:', error);
    res.status(500).json({ message: 'Konusmalar getirilemedi', error: error.message });
  }
});

// Get messages for a listing + peer
router.get('/:listingId/:otherUserId', auth, async (req, res) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 10;

    const total = await Message.countDocuments({
      listing: req.params.listingId,
      $or: [
        { sender: req.userId, receiver: req.params.otherUserId },
        { sender: req.params.otherUserId, receiver: req.userId }
      ]
    });

    const skip = Math.max(0, total - (page * limit));
    const actualLimit = Math.min(limit, total - skip);

    const messages = await Message.find({
      listing: req.params.listingId,
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

    res.json({
      messages,
      hasMore: skip > 0,
      total,
      page,
      limit
    });
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ message: 'Mesajlar getirilemedi', error: error.message });
  }
});

// Send message
router.post('/', auth, async (req, res) => {
  try {
    const { listing, receiver, content } = req.body;

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

    res.status(201).json(message);
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ message: 'Mesaj gonderilemedi', error: error.message });
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
    console.error('Mark read error:', error);
    res.status(500).json({ message: 'Islem basarisiz', error: error.message });
  }
});

module.exports = router;
