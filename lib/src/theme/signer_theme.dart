import 'package:flutter/material.dart';

abstract final class SignerColors {
  static const background = Color(0xFF0E1412);
  static const surface = Color(0xFF151C19);
  static const surfaceRaised = Color(0xFF1C2521);
  static const gold = Color(0xFFE8C26A);
  static const goldSoft = Color(0xFF24251B);
  static const mint = Color(0xFF8ED1AE);
  static const mintSoft = Color(0xFF1C2B24);
  static const text = Color(0xFFEDF2EE);
  static const textMuted = Color(0xFF9BA8A1);
  static const border = Color(0xFF26312C);
  static const destructive = Color(0xFFF0A58F);
}

class SignerBackground extends StatelessWidget {
  const SignerBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: SignerColors.background, child: child);
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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: SignerColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: SignerColors.border),
    ),
    child: child,
  );
}

/// A scrollable task with actions kept in reach, including with a large text size.
class SignerPage extends StatelessWidget {
  const SignerPage({
    super.key,
    this.title,
    this.description,
    this.header,
    required this.children,
    this.footer,
    this.onBack,
  });
  final String? title, description;
  final Widget? header, footer;
  final List<Widget> children;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child:
                    header ??
                    Row(
                      children: [
                        if (onBack != null) BackControl(onPressed: onBack!),
                        const Spacer(),
                        const TestnetBadge(),
                      ],
                    ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      if (description != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          description!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      if (title != null || description != null)
                        const SizedBox(height: 28),
                      ...children,
                    ],
                  ),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BackControl extends StatelessWidget {
  const BackControl({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    onPressed: onPressed,
    tooltip: 'Go back',
    style: IconButton.styleFrom(
      backgroundColor: SignerColors.surface,
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    icon: const Icon(Icons.arrow_back_rounded, size: 21),
  );
}

class TestnetBadge extends StatelessWidget {
  const TestnetBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: SignerColors.goldSoft,
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'Testnet',
      style: TextStyle(
        color: SignerColors.gold,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class ZignerBrand extends StatelessWidget {
  const ZignerBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SignerColors.mintSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(painter: _ZPainter()),
      ),
      const SizedBox(width: 10),
      const Flexible(
        child: Text(
          'Zigner',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: SignerColors.text,
          ),
        ),
      ),
    ],
  );
}

class _ZPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(12, 12)
        ..lineTo(28, 12)
        ..lineTo(12, 28)
        ..lineTo(28, 28),
      Paint()
        ..color = SignerColors.mint
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, required this.onBack});
  final int step;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      BackControl(onPressed: onBack),
      const SizedBox(width: 20),
      Expanded(
        child: Row(
          children: [
            for (var i = 1; i <= 4; i++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? SignerColors.mint : SignerColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Text('$step of 4', style: const TextStyle(fontSize: 12)),
    ],
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.color = SignerColors.mint,
  });
  final IconData icon;
  final String title, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: SignerColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(detail, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

class QuietNotice extends StatelessWidget {
  const QuietNotice(this.text, {super.key, this.warning = false});
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning ? SignerColors.goldSoft : SignerColors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline_rounded : Icons.shield_outlined,
          color: warning ? SignerColors.gold : SignerColors.mint,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: warning ? SignerColors.gold : SignerColors.textMuted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
      ],
    ),
  );
}
