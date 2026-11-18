import 'package:flutter/material.dart';

import '../../services/chat_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENUMS
// ─────────────────────────────────────────────────────────────────────────────
enum MessageType   { text, emoji, voice, appointment, image, file }
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
  // Pin/mute/archive are persisted per room in SQLite (ChatDB);
  // group flag + member user IDs are API-only (not in SQLite).
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
  // True when the send's server echo never arrived (see
  // ChatRoomConnection.sendTimeouts): the bubble shows a failed
  // state with a tap-to-retry affordance. Not persisted — a failed
  // send is retried or dropped in the same session.
  bool sendFailed;
  ChatMessage? replyTo;
  Map<String, int> reactions;
  String? myReaction;
  final String? voiceDuration;
  // For appointment messages
  final String? appointmentTitle;
  final String? appointmentDate;
  final String? appointmentTime;
  // Backend appointment id embedded in a shared appointment card
  // ("📅 Appointment [id]: …"). Null for old shares without an id.
  final int? appointmentId;
  // When the message was created (server time for API messages).
  // Used for the date separators; null for old cached messages that
  // predate the column.
  final DateTime? createdAt;
  // For image messages
  final Color? imageColor;
  // For image/file messages from the API: the original file name and
  // size in bytes. Old messages lack them (null). `text` holds the
  // media URL for these messages.
  final String? fileName;
  final int? fileSize;

  /// One-line text for the inbox preview and reply quotes. Media
  /// messages carry a URL in [text], which must never be shown raw.
  String get previewText {
    switch (type) {
      case MessageType.image:
        return 'Photo';
      case MessageType.file:
        return fileName != null && fileName!.isNotEmpty ? fileName! : 'File';
      case MessageType.voice:
        return 'Voice message';
      case MessageType.appointment:
        return 'Appointment: ${appointmentTitle ?? 'Consultation'}';
      default:
        return text;
    }
  }

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
    this.sendFailed = false,
    this.replyTo,
    Map<String, int>? reactions,
    this.myReaction,
    this.voiceDuration,
    this.appointmentTitle,
    this.appointmentDate,
    this.appointmentTime,
    this.appointmentId,
    this.createdAt,
    this.imageColor,
    this.fileName,
    this.fileSize,
  }) : reactions = reactions ?? {};

  /// Maps a backend message to the local model. [currentUserId] is
  /// the logged-in user's ID (as a string) — it decides [fromMe].
  /// The backend has no reactions or stars, so those stay at their
  /// local defaults; replies come from the server's `reply_to_*`
  /// fields when present. Voice notes and shared appointment
  /// cards are detected from the payload: voice notes arrive as
  /// `file` messages whose name starts with `voice_note_` (or ends
  /// in `.m4a`), and appointment shares are text messages starting
  /// with the `📅 Appointment` prefix (see [_parseAppointmentShare]).
  /// [otherMemberIds] is every other member of the room: in a group
  /// a message is only `read` once ALL of them read it; in a 1:1
  /// room that is just the peer. When it is null/empty the old
  /// any-reader rule is used as a fallback.
  factory ChatMessage.fromApi(
    ChatApiMessage msg, {
    required String? currentUserId,
    List<String>? otherMemberIds,
  }) {
    final fromMe = currentUserId != null && msg.senderId == currentUserId;
    // read_by always contains the sender; read means every OTHER
    // member read it (in a 1:1 room: the peer). The old "any other
    // user" rule was wrong for groups.
    final others = otherMemberIds
            ?.where((id) => id != msg.senderId)
            .toList() ??
        const <String>[];
    final read =
        fromMe &&
        (others.isNotEmpty
            ? others.every((id) => msg.readBy.contains(id))
            : msg.readBy.any((id) => id != msg.senderId));
    final appt = msg.messageType == 'text'
        ? _parseAppointmentShare(msg.content)
        : null;
    final isVoice =
        msg.messageType == 'voice' ||
        (msg.messageType == 'file' && _looksLikeVoiceNote(msg.fileName));
    // Server reply quote (broadcast `reply_to_id`/`reply_to_text`).
    // The quoted message's sender is unknown from the quote alone,
    // so `fromMe` is left false — the thread keeps its richer local
    // quote for my own echoed sends.
    final serverReply = (msg.replyToId != null && msg.replyToId!.isNotEmpty)
        ? ChatMessage(
            id: msg.replyToId!,
            text: msg.replyToText ?? '',
            fromMe: false,
            time: '',
            type: MessageType.text,
          )
        : null;
    return ChatMessage(
      id: msg.id.isNotEmpty
          ? msg.id
          : '${msg.roomId}_${msg.createdAt.millisecondsSinceEpoch}',
      text: msg.content,
      fromMe: fromMe,
      time: _fmtTime(msg.createdAt.toLocal()),
      createdAt: msg.createdAt,
      type: appt != null
          ? MessageType.appointment
          : isVoice
              ? MessageType.voice
              : switch (msg.messageType) {
                  'image' => MessageType.image,
                  'file' => MessageType.file,
                  _ => MessageType.text,
                },
      status: fromMe
          ? (read ? MessageStatus.read : MessageStatus.delivered)
          : MessageStatus.delivered,
      replyTo: serverReply,
      fileName: msg.fileName,
      fileSize: msg.fileSize,
      appointmentId: appt?.id,
      appointmentTitle: appt?.title,
      appointmentDate: appt?.date,
      appointmentTime: appt?.time,
    );
  }

  /// True when [fileName] looks like a recorded voice note: the
  /// recorder names them `voice_note_<ts>.m4a`, and any `.m4a` file
  /// is audio the voice player can handle. Pure.
  static bool _looksLikeVoiceNote(String? fileName) {
    if (fileName == null) return false;
    final lower = fileName.toLowerCase();
    return lower.startsWith('voice_note_') || lower.endsWith('.m4a');
  }

  /// Parse a shared appointment card out of message text. Shares are
  /// sent as `📅 Appointment [id]: Name — Service\nDate at Time •
  /// status` (see `ChatThreadScreen._shareAppointment`); forwards
  /// use the single-line form `📅 Appointment [id]: Title — Date at
  /// Time`. Returns null when the text is not a share — a user just
  /// typing "📅 Appointment…" without the colon is plain text.
  /// Pure.
  static ({int? id, String title, String date, String time})?
  _parseAppointmentShare(String content) {
    const prefix = '📅 Appointment';
    if (!content.startsWith(prefix)) return null;
    var rest = content.substring(prefix.length);
    int? id;
    final idMatch = RegExp(r'^\s*\[(\d+)\]:').firstMatch(rest);
    if (idMatch != null) {
      id = int.tryParse(idMatch.group(1)!);
      rest = rest.substring(idMatch.end);
    } else if (rest.startsWith(':')) {
      rest = rest.substring(1);
    } else {
      return null;
    }
    rest = rest.trimLeft();
    if (rest.isEmpty) return (id: id, title: 'Consultation', date: '', time: '');
    final lines = rest.split('\n');
    final firstLine = lines.first.trim();
    // Date/time source: the second line of a share ("Date at Time •
    // status"), or the part after " — " in a single-line forward.
    String? dateTimePart;
    String title = firstLine;
    if (lines.length > 1) {
      dateTimePart = lines[1].split(' • ').first.trim();
    } else {
      final dash = firstLine.indexOf(' — ');
      if (dash >= 0 && firstLine.substring(dash + 3).contains(' at ')) {
        title = firstLine.substring(0, dash).trim();
        dateTimePart = firstLine.substring(dash + 3).trim();
      }
    }
    var date = '';
    var time = '';
    if (dateTimePart != null) {
      final at = dateTimePart.indexOf(' at ');
      if (at >= 0) {
        date = dateTimePart.substring(0, at).trim();
        time = dateTimePart.substring(at + 4).trim();
      }
    }
    return (id: id, title: title, date: date, time: time);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DATE SEPARATORS (pure — unit-tested)
// ─────────────────────────────────────────────────────────────────────────────
/// Date-separator rules for the thread list, extracted as pure
/// functions so they are unit-testable.
///
/// A message with a null `createdAt` (an old cached row from before
/// the column existed) must NEVER silently merge into the previous
/// day's group — that was the "sent 18 Nov, shown under Nov 17" bug.
/// Instead it takes the effective date of its nearest dated
/// neighbour (next dated message first, else the previous one), so
/// it still gets its own separator when the day changes.
class DateSeparators {
  /// Effective date of message [i]: its own `createdAt`, or the
  /// nearest dated neighbour's when its own is null. Null only when
  /// NO message in [dates] has a date.
  static DateTime? effectiveDate(List<DateTime?> dates, int i) {
    final own = dates[i];
    if (own != null) return own;
    for (var j = i + 1; j < dates.length; j++) {
      if (dates[j] != null) return dates[j];
    }
    for (var j = i - 1; j >= 0; j--) {
      if (dates[j] != null) return dates[j];
    }
    return null;
  }

  /// True when a separator belongs above message [i]: above the
  /// first message, and above the first message of each new
  /// (effective) day.
  static bool showSeparator(List<DateTime?> dates, int i) {
    if (i == 0) return true;
    final a = effectiveDate(dates, i);
    final b = effectiveDate(dates, i - 1);
    if (a == null || b == null) return a != b;
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year != lb.year || la.month != lb.month || la.day != lb.day;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RECENT EMOJIS (in-memory — unit-testable via [record]/[recent])
// ─────────────────────────────────────────────────────────────────────────────
/// Recently used emojis for the "Recent" tab, tracked in memory for
/// the session (most recent first, max 16). The tab used to be a
/// hardcoded static list; it now reflects what was actually sent.
class RecentEmojis {
  static const maxRecent = 16;

  static final List<String> _recent = [];

  /// Most recently used emojis, most recent first. Empty until the
  /// user sends an emoji.
  static List<String> get recent => List.unmodifiable(_recent);

  static void record(String emoji) {
    _recent.remove(emoji);
    _recent.insert(0, emoji);
    if (_recent.length > maxRecent) {
      _recent.removeRange(maxRecent, _recent.length);
    }
  }

  /// Test-only reset.
  static void debugReset() => _recent.clear();
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
