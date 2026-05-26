import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Colored-circle avatar with the user's initial. Color is derived
/// deterministically from the username so the same user always gets the
/// same colour across sessions. When `talking` is true, a soft animated
/// ring pulses around the circle.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.size = 28,
    this.talking = false,
    this.muted = false,
  });

  final String name;
  final double size;
  final bool talking;
  final bool muted;

  Color get _bg => _colourForName(name);

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bg,
        gradient: RadialGradient(
          colors: [
            _bg.withValues(alpha: 1.0),
            Color.lerp(_bg, Colors.black, 0.30)!,
          ],
          radius: 0.9,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (talking)
          _SpeakingRing(size: size, color: AppColors.speaking),
        circle,
        if (muted)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bg1,
                border: Border.all(color: AppColors.bg1, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.mic_off_rounded,
                size: size * 0.28,
                color: AppColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpeakingRing extends StatefulWidget {
  const _SpeakingRing({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  State<_SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<_SpeakingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final spread = 4.0 + 4.0 * t;
        final opacity = (1.0 - t).clamp(0.0, 1.0);
        return Container(
          width: widget.size + spread,
          height: widget.size + spread,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: opacity),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

// A palette of saturated-but-readable colours; pick by hashing the name.
const List<Color> _palette = [
  Color(0xFF5B8DEF),
  Color(0xFFE07C72),
  Color(0xFF60C4A1),
  Color(0xFFE0B95B),
  Color(0xFFB07CFF),
  Color(0xFF4ADE80),
  Color(0xFFFF9F66),
  Color(0xFF55C0E0),
  Color(0xFFD46BB8),
  Color(0xFF9CA88B),
];

Color _colourForName(String name) {
  if (name.isEmpty) return _palette[0];
  int h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _palette[h % _palette.length];
}
