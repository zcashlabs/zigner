import 'package:airgapped_zcash_signer/src/rust/api/vizor.dart';
import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:airgapped_zcash_signer/src/screens/signature_screen.dart';
import 'package:airgapped_zcash_signer/src/theme/signer_theme.dart';
import 'package:airgapped_zcash_signer/src/util/zec_format.dart';
import 'package:flutter/material.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.review, required this.cbor});

  final BatchReview review;
  final List<int> cbor;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _confirmed = false;
  bool _signing = false;
  String? _signError;

  Future<void> _sign() async {
    if (_signing) return;
    setState(() {
      _signing = true;
      _signError = null;
    });
    try {
      final signature = signVizorBatch(
        cbor: widget.cbor,
        seed: await const SeedVault().readSeed(),
        accountIndex: 0,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => SignatureScreen(signature: signature),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('signVizorBatch failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _signError = error.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    return Scaffold(
      appBar: AppBar(title: const Text('Review transaction')),
      body: SignerBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: SignerColors.goldSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF594718)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.science_rounded,
                      color: SignerColors.gold,
                      size: 19,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'VIZOR PCZT  ·  TESTNET',
                        style: TextStyle(
                          color: SignerColors.gold,
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'YOU ARE SENDING',
                style: TextStyle(
                  color: SignerColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${review.transactionCount} transaction${review.transactionCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _Tag(
                    label: 'ORCHARD ${review.orchardSpendCount}',
                    icon: Icons.shield_rounded,
                  ),
                  _Tag(
                    label: 'IRONWOOD ${review.ironwoodSpendCount}',
                    icon: Icons.public_off_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SignerCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRANSACTION DETAILS',
                      style: TextStyle(
                        color: SignerColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Detail(
                      label: 'Visible outputs',
                      value: formatZec(review.visibleOutputTotalZat),
                    ),
                    for (final (index, output) in review.outputs.indexed) ...[
                      const Divider(height: 30, color: SignerColors.border),
                      _Detail(
                        label: 'Output ${index + 1}',
                        value: output,
                        mono: true,
                      ),
                    ],
                    const Divider(height: 30, color: SignerColors.border),
                    _Detail(
                      label: 'Request ID',
                      value: review.requestIdHex,
                      mono: true,
                    ),
                    const Divider(height: 30, color: SignerColors.border),
                    _Detail(
                      label: 'Request fingerprint',
                      value: review.requestDigest,
                      mono: true,
                    ),
                  ],
                ),
              ),
              if (review.warnings.isNotEmpty) ...[
                const SizedBox(height: 18),
                ...review.warnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 19,
                          color: SignerColors.gold,
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: Text(warning)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Material(
                color: _confirmed
                    ? const Color(0xFF14271F)
                    : SignerColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: _confirmed
                        ? const Color(0xFF24503C)
                        : SignerColors.border,
                  ),
                ),
                child: CheckboxListTile(
                  value: _confirmed,
                  activeColor: SignerColors.mint,
                  checkColor: SignerColors.background,
                  onChanged: (value) =>
                      setState(() => _confirmed = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I verified the amount and recipient.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'This confirmation is required to continue.',
                  ),
                ),
              ),
              if (_signError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _signError!,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _confirmed && !_signing ? _sign : null,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(
                  _signing ? 'Signing PCZT…' : 'Approve and sign PCZT',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: SignerColors.textMuted,
              fontSize: 10,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : null,
              color: SignerColors.text,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: SignerColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SignerColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SignerColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}
