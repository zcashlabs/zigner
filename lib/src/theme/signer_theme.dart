import 'package:flutter/material.dart';

abstract final class SignerColors {
  static const background = Color(0xFF090B0D);
  static const surface = Color(0xFF121519);
  static const surfaceRaised = Color(0xFF191D22);
  static const gold = Color(0xFFFFC83D);
  static const goldSoft = Color(0xFF342B16);
  static const mint = Color(0xFF5EE6A8);
  static const text = Color(0xFFF5F2EA);
  static const textMuted = Color(0xFF969CA5);
  static const border = Color(0xFF292E35);
}

class SignerBackground extends StatelessWidget {
  const SignerBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121518), SignerColors.background],
          stops: [0, 0.55],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -170,
            right: -130,
            child: Container(
              width: 330,
              height: 330,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33FFC83D), Color(0x00FFC83D)],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class SignerCard extends StatelessWidget {
  const SignerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: SignerColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: SignerColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}
