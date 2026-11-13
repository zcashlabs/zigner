import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:airgapped_zcash_signer/src/rust/api/vizor.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  int _progress = 0;
  String? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    resetVizorScan();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finishing || capture.barcodes.isEmpty) return;
    final payload = capture.barcodes.first.rawValue;
    if (payload == null || payload.isEmpty) return;
    try {
      final result = receiveVizorUrPart(part_: payload);
      if (!mounted) return;
      setState(() {
        _progress = result.progress.toInt();
        _error = null;
      });
      if (result.complete && result.cbor != null) {
        _finishing = true;
        Navigator.of(context).pop(result.cbor);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    resetVizorScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    onBack: () => Navigator.pop(context),
    title: 'Scan a request.',
    description: 'Point your camera at the animated QR in Vizor. It reads automatically.',
    footer: const Text(
      'Your camera reads requests only. Nothing is signed until you review and unlock.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, height: 1.5),
    ),
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, error) => const ColoredBox(
                  color: SignerColors.surface,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Camera unavailable. Allow camera access in Android Settings, then return to scan.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CustomPaint(painter: _ScannerFramePainter()),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      LinearProgressIndicator(
        value: _progress / 100,
        minHeight: 4,
        borderRadius: BorderRadius.circular(4),
        color: SignerColors.mint,
        backgroundColor: SignerColors.border,
      ),
      const SizedBox(height: 12),
      Text(
        _progress == 0
            ? 'Waiting for a request'
            : 'Reading animated QR · $_progress%',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      QuietNotice(
        _error ?? 'Hold the phone steady, about 20 cm from the screen. Keep the whole QR inside the frame.',
        warning: _error != null,
      ),
    ],
  );
}

class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SignerColors.mint
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const corner = 42.0;
    final path = Path()
      ..moveTo(0, corner)
      ..lineTo(0, 0)
      ..lineTo(corner, 0)
      ..moveTo(size.width - corner, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, corner)
      ..moveTo(size.width, size.height - corner)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - corner, size.height)
      ..moveTo(corner, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - corner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
