import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AnimatedUrQr extends StatefulWidget {
  const AnimatedUrQr({super.key, required this.parts, this.size = 270});

  final List<String> parts;
  final double size;

  @override
  State<AnimatedUrQr> createState() => _AnimatedUrQrState();
}

class _AnimatedUrQrState extends State<AnimatedUrQr> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant AnimatedUrQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parts != widget.parts) {
      _index = 0;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.parts.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        if (mounted) {
          setState(() => _index = (_index + 1) % widget.parts.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parts.isEmpty) return const Text('No QR response is available.');
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          widget.size,
          math.max(0.0, constraints.maxWidth - 24),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: widget.parts[_index],
                    size: size,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.parts.length == 1
                  ? 'Keep this code in view'
                  : 'Animated QR · ${_index + 1} / ${widget.parts.length}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}
