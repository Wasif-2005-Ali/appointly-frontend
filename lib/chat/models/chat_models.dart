import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENUMS
// ─────────────────────────────────────────────────────────────────────────────
enum MessageType   { text, emoji, voice, appointment, image }
enum MessageStatus { sent, delivered, read }

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
  });

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
