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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SignerColors.background,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text('Scan signing request'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 290,
                height: 290,
                child: CustomPaint(painter: _ScannerFramePainter()),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xDD121519),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SignerColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: SignerColors.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error ??
                          (_progress == 0
                              ? 'Scan the animated QR shown by Vizor'
                              : 'Reading animated QR · $_progress%'),
                      style: const TextStyle(
                        color: SignerColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SignerColors.gold
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
