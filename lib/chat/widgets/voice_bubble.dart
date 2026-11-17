import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VOICE MESSAGE TILE — honest static rendering
// ─────────────────────────────────────────────────────────────────────────────
// Voice notes recorded before real voice notes existed were stored
// on-device only (a duration string, no audio file), so there is
// nothing to play back. This tile shows the duration and says so —
// it never simulates playback with a fake waveform. New voice notes
// are real .m4a files uploaded via the media endpoint and arrive as
// file messages instead (see ChatThreadScreen._finishRecording).
class VoiceBubble extends StatelessWidget {
  final String duration;
  final bool isMe;
  final Color accent;
  final List<Color> btnGrad;

  const VoiceBubble({
    super.key,
    required this.duration,
    required this.isMe,
    required this.accent,
    required this.btnGrad,
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = isMe ? Colors.white : accent;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.22)
              : accent.withOpacity(0.13),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.mic_rounded, color: fgColor, size: 24),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Voice message',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$duration • recorded on this device',
            style: GoogleFonts.dmSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: fgColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    ]);
  }
}
