import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Colored circle with the user's initial. Colour is derived deterministically
/// from the username so the same user always renders the same. When `talking`
/// is true a soft pulsing ring appears around it. The ring is rendered inside
/// a fixed-size box so turning it on or off doesn't shift surrounding layout.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.size = 28,
    this.talking = false,
  });

  final String name;
  final double size;
  final bool talking;

  Color get _bg => _colourForName(name);

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    // Reserve room for the ring so adding/removing it never reflows the row.
    final reserved = size + _kRingMaxSpread;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [_bg, Color.lerp(_bg, Colors.black, 0.30)!],
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
    return SizedBox(
      width: reserved,
      height: reserved,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _SpeakingRing(size: size, visible: talking),
          circle,
        ],
      ),
    );
  }
}

// Maximum extra space (in px) the ring takes around the avatar.
const double _kRingMaxSpread = 6;

class _SpeakingRing extends StatefulWidget {
  const _SpeakingRing({required this.size, required this.visible});
  final double size;
  final bool visible;

  @override
  State<_SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<_SpeakingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void didUpdateWidget(covariant _SpeakingRing old) {
    super.didUpdateWidget(old);
    if (widget.visible && !_c.isAnimating) _c.repeat();
    if (!widget.visible && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final spread = _kRingMaxSpread * t;
          final ringOpacity = (1.0 - t).clamp(0.0, 1.0);
          return SizedBox(
            width: widget.size + _kRingMaxSpread,
            height: widget.size + _kRingMaxSpread,
            child: Center(
              child: Container(
                width: widget.size + spread,
                height: widget.size + spread,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.speaking.withValues(alpha: ringOpacity),
                    width: 2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
