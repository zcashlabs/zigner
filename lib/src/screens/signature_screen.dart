import 'package:airgapped_zcash_signer/src/rust/api/vizor.dart';
import 'package:airgapped_zcash_signer/src/widgets/animated_ur_qr.dart';
import 'package:flutter/material.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';

class SignatureScreen extends StatelessWidget {
  const SignatureScreen({super.key, required this.signature});

  final SignedBatch signature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signed response')),
      body: SignerBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              const Center(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: SignerColors.mint,
                  size: 58,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Response ready',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Scan this QR with the online wallet to return the signed response.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: const [
                        BoxShadow(color: Color(0x44FFC83D), blurRadius: 36),
                      ],
                    ),
                    child: AnimatedUrQr(parts: signature.urParts, size: 280),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SignerColors.goldSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF594718)),
                ),
                child: Text(
                  '${signature.signatureCount} spend signature${signature.signatureCount == 1 ? '' : 's'} created for request ${signature.requestIdHex.substring(0, 12)}…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SignerColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SignerCard(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  signature.urParts.join('\n'),
                  style: const TextStyle(
                    color: SignerColors.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Finish session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
