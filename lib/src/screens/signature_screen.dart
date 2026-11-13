import 'package:flutter/material.dart';

import '../rust/api/vizor.dart';
import '../theme/signer_theme.dart';
import '../widgets/animated_ur_qr.dart';

class SignatureScreen extends StatelessWidget {
  const SignatureScreen({super.key, required this.signature});
  final SignedBatch signature;
  @override
  Widget build(BuildContext context) => SignerPage(
    header: const Row(
      children: [
        Expanded(child: ZignerBrand()),
        SizedBox(width: 12),
        TestnetBadge(),
      ],
    ),
    title: 'Signed.\nNow show this to Vizor.',
    description: 'Scan this animated QR with Vizor to pass the signatures back. Keep this screen open until it finishes.',
    footer: FilledButton(
      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      child: const Text('Done'),
    ),
    children: [
      const Center(
        child: Icon(
          Icons.check_circle_outline_rounded,
          color: SignerColors.mint,
          size: 48,
        ),
      ),
      const SizedBox(height: 24),
      Center(child: AnimatedUrQr(parts: signature.urParts)),
      const SizedBox(height: 24),
      SignerCard(
        child: InfoRow(
          icon: Icons.check_rounded,
          title: '${signature.signatureCount} spend signatures ready',
          detail: 'Request ${signature.requestIdHex}',
        ),
      ),
      const SizedBox(height: 16),
      const QuietNotice(
        'Your keys stay here. Vizor will finalize and broadcast the transaction after receiving this response.',
      ),
    ],
  );
}
