import 'package:flutter/material.dart';

import '../../services/chat_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENUMS
// ─────────────────────────────────────────────────────────────────────────────
enum MessageType   { text, emoji, voice, appointment, image }
enum MessageStatus { sent, delivered, read }

// Deterministic avatar palette for API rooms (no avatar data on the
// backend), following the Appointment model's approach.
const _apiAvatarColors = [
  Color(0xFF4A90D9),
  Color(0xFF7C5CBF),
  Color(0xFF2ECC96),
  Color(0xFFE8805A),
  Color(0xFF3B73C0),
  Color(0xFF2A6AB5),
];

Color _avatarColorFor(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _apiAvatarColors[hash % _apiAvatarColors.length];
}

/// "9:05 PM" — the same time format the thread screen uses locally.
String _fmtTime(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? "AM" : "PM"}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  CONVERSATION MODEL
// ─────────────────────────────────────────────────────────────────────────────
class ChatConversation {
  final String id, name, service;
  final Color avatarColor;
  bool online;
  String lastMsg, time;
  int unread;
  bool isPinned, isMuted, isArchived;
  // API-only fields (not in SQLite): group flag + member user IDs.
  final bool isGroup;
  final List<String> participantIds;

  ChatConversation({
    required this.id,
    required this.name,
    required this.service,
    required this.avatarColor,
    required this.online,
    required this.lastMsg,
    required this.time,
    required this.unread,
    this.isPinned = false,
    this.isMuted  = false,
    this.isArchived = false,
    this.isGroup = false,
    this.participantIds = const [],
  });

  /// Maps a backend room to the local conversation model. The room
  /// list carries no last message, unread count, or presence, so
  /// those start empty/false and are filled in by the inbox's
  /// preview fetch (and by an opened thread).
  factory ChatConversation.fromApi(ChatRoomInfo room) => ChatConversation(
    id: room.roomId,
    name: room.name,
    service: room.isGroup ? 'Group chat' : 'Direct message',
    avatarColor: _avatarColorFor(room.roomId),
    online: false,
    lastMsg: 'No messages yet',
    time: '',
    unread: 0,
    isGroup: room.isGroup,
    participantIds: room.participants,
  );

  String get initials {
    final parts = name.split(' ');
    return parts.length >= 2 ? '${parts[0][0]}${parts[1][0]}' : name[0];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MESSAGE MODEL
// ─────────────────────────────────────────────────────────────────────────────
class ChatMessage {
  final String id;
  String text;
  final String time;
  final bool fromMe;
  final MessageType type;
  MessageStatus status;
  bool isStarred, isDeleted, isForwarded;
  ChatMessage? replyTo;
  Map<String, int> reactions;
  String? myReaction;
  final String? voiceDuration;
  // For appointment messages
  final String? appointmentTitle;
  final String? appointmentDate;
  final String? appointmentTime;
  // For image messages
  final Color? imageColor;

  ChatMessage({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.time,
    required this.type,
    this.status    = MessageStatus.sent,
    this.isStarred = false,
    this.isDeleted = false,
    this.isForwarded = false,
    this.replyTo,
    Map<String, int>? reactions,
    this.myReaction,
    this.voiceDuration,
    this.appointmentTitle,
    this.appointmentDate,
    this.appointmentTime,
    this.imageColor,
  }) : reactions = reactions ?? {};

  /// Maps a backend message to the local model. [currentUserId] is
  /// the logged-in user's ID (as a string) — it decides [fromMe].
  /// The backend has no replies, reactions, stars, or voice notes,
  /// so those stay at their local defaults.
  factory ChatMessage.fromApi(
    ChatApiMessage msg, {
    required String? currentUserId,
  }) {
    final fromMe = currentUserId != null && msg.senderId == currentUserId;
    // read_by always contains the sender; anyone else means read.
    final read = fromMe && msg.readBy.any((id) => id != msg.senderId);
    return ChatMessage(
      id: msg.id.isNotEmpty
          ? msg.id
          : '${msg.roomId}_${msg.createdAt.millisecondsSinceEpoch}',
      text: msg.content,
      fromMe: fromMe,
      time: _fmtTime(msg.createdAt.toLocal()),
      type: msg.messageType == 'image'
          ? MessageType.image
          : MessageType.text,
      status: fromMe
          ? (read ? MessageStatus.read : MessageStatus.delivered)
          : MessageStatus.delivered,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATUS STORY MODEL
// ─────────────────────────────────────────────────────────────────────────────
class StatusStory {
  final String name;
  final Color color;
  final bool viewed, isMe;

  const StatusStory(this.name, this.color, {this.viewed = false, this.isMe = false});

  String get initials {
    final p = name.split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}' : name[0];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NEW CONTACT MODEL
// ─────────────────────────────────────────────────────────────────────────────
class NewContact {
  final String name, service;
  final Color color;
  final bool online;

  const NewContact(this.name, this.service, this.color, this.online);

  String get initials {
    final p = name.split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}' : name[0];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMOJI CATEGORY MODEL
// ─────────────────────────────────────────────────────────────────────────────
class EmojiCategory {
  final String label, icon;
  final List<String> emojis;
  const EmojiCategory(this.label, this.icon, this.emojis);
}

const emojiCategories = [
  EmojiCategory('Recent',  '🕐', ['😀','😂','❤️','👍','😊','🙏','🔥','💯','😍','🤣','✅','👏','🎉','💪','🫶','🥰']),
  EmojiCategory('Smileys', '😀', ['😀','😁','😂','🤣','😃','😄','😅','😆','😉','😊','😋','😎','😍','🥰','😘','😗','😙','😚','🙂','🤗','🤩','🤔','🤨','😐','😑','😶','🙄','😏','😣','😥','😮','🤐','😯','😪','😫','🥱','😴','😌','😛','😜','😝','🤤','😒','😓','😔','😕','🙃','🤑','😲','🙁','😖','😞','😟','😤','😢','😭','😦','😧','😨','😩','🤯','😬','🥵','🥶','😱','😳','🤪','😵','😡','😠','🤬','😷','🤒','🤕','🤢','🤮','🤧','🥴','😇','🥳','🥺','🤠','🤡','🤥','🤫','🤭','🧐','🤓','😈','👿','💩','👻','💀','☠️','👽','👾','🤖']),
  EmojiCategory('People',  '👋', ['👋','🤚','🖐️','✋','🖖','👌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','✍️','💅','💪','🦾','👀','👄','👶','👧','🧒','👦','👩','🧑','👨','👵','🧓','👴']),
  EmojiCategory('Animals', '🐶', ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🦋','🐛','🐌','🐞','🐜','🦒','🐘','🦏','🦛']),
  EmojiCategory('Food',    '🍎', ['🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🧄','🧅','🥔','🍠','🥐','🥯','🍞','🥖','🥨','🧀','🥚','🍳','🧈','🥞','🧇','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🥪','🥙']),
  EmojiCategory('Travel',  '✈️', ['🌍','🌎','🌏','🌐','🗺️','🧭','🏔️','⛰️','🌋','🗻','🏕️','🏖️','🏜️','🏝️','🏠','🏡','🏢','🏥','🏦','🏨','🏪','🏫','🏬','🚗','🚕','🚙','🚌','🏎️','🚓','🚑','🚒','✈️','🛩️','🛫','🛬','💺','🚁','🚂','🚄','🚅','🚆','🚇','🚈']),
  EmojiCategory('Symbols', '❤️', ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❤️‍🔥','❤️‍🩹','💕','💞','💓','💗','💖','💝','💘','💟','☮️','✝️','☪️','🕉️','☯️','✡️','💯','💢','⚠️','🔰','♻️','✅','❌','⭕','🛑','⛔','📛','🚫','⭐','🌟','💫','✨','🔥','🌈','☀️','❄️','🌊']),
];
