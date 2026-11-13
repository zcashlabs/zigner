import 'package:flutter/material.dart';

import '../rust/api/vizor.dart';
import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';
import '../util/zec_format.dart';
import 'signature_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.review, required this.cbor});
  final BatchReview review;
  final List<int> cbor;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _confirmed = false;
  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    return SignerPage(
      onBack: () => Navigator.pop(context),
      title: 'Take a moment.\nCheck the request.',
      description: 'Only approve a request you intended to make in Vizor.',
      footer: FilledButton.icon(
        onPressed: _confirmed
            ? () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ConfirmSignScreen(review: review, cbor: widget.cbor),
                ),
              )
            : null,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('Continue to signing'),
      ),
      children: [
        SignerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VISIBLE OUTPUTS',
                style: TextStyle(fontSize: 11, letterSpacing: 1.3),
              ),
              const SizedBox(height: 10),
              Text(
                formatZec(review.visibleOutputTotalZat),
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(color: SignerColors.mint),
              ),
              const SizedBox(height: 14),
              Text(
                '${review.transactionCount} transaction${review.transactionCount == 1 ? '' : 's'} · Testnet',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                'This total may include change. Hidden outputs and the fee are not fully represented here.',
                style: TextStyle(fontSize: 13, height: 1.55),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final (index, output) in review.outputs.indexed) ...[
          SignerCard(child: _detail('Output ${index + 1}', output, mono: true)),
          const SizedBox(height: 12),
        ],
        SignerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _detail('Network fee', 'Not supplied by this review'),
              const Divider(height: 32),
              _detail(
                'Spend counts',
                '${review.orchardSpendCount} Orchard · ${review.ironwoodSpendCount} Ironwood',
              ),
              const Divider(height: 32),
              _detail('Request ID', review.requestIdHex, mono: true),
              const Divider(height: 32),
              _detail('Request fingerprint', review.requestDigest, mono: true),
            ],
          ),
        ),
        for (final warning in review.warnings) ...[
          const SizedBox(height: 12),
          QuietNotice(warning, warning: true),
        ],
        const SizedBox(height: 24),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v ?? false),
          title: const Text(
            'I reviewed the visible outputs and the review limitations.',
            style: TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _detail(String label, String value, {bool mono = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: SignerColors.textMuted),
      ),
      const SizedBox(height: 8),
      SelectableText(
        value,
        style: TextStyle(
          color: SignerColors.text,
          fontFamily: mono ? 'JetBrainsMono' : 'Inter',
          fontSize: 14,
          height: 1.6,
        ),
      ),
    ],
  );
}

class ConfirmSignScreen extends StatefulWidget {
  const ConfirmSignScreen({
    super.key,
    required this.review,
    required this.cbor,
  });
  final BatchReview review;
  final List<int> cbor;
  @override
  State<ConfirmSignScreen> createState() => _ConfirmSignScreenState();
}

class _ConfirmSignScreenState extends State<ConfirmSignScreen> {
  bool _signing = false;
  String? _error;
  Future<void> _sign() async {
    if (_signing) return;
    setState(() {
      _signing = true;
      _error = null;
    });
    try {
      final seed = await const SeedVault().readSeed();
      late final SignedBatch signature;
      try {
        if (!mounted) return;
        signature = signVizorBatch(
          cbor: widget.cbor,
          seed: seed,
          accountIndex: 0,
        );
      } finally {
        seed.fillRange(0, seed.length, 0);
      }
      if (!mounted) return;
      Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
          builder: (_) => SignatureScreen(signature: signature),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is Exception ? vaultErrorMessage(e) : '$e');
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_signing,
    child: SignerPage(
      onBack: _signing ? null : () => Navigator.pop(context),
      title: 'Ready to sign?',
      description: 'Unlock with Android to create signatures for the request you just reviewed.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _signing ? null : _sign,
            icon: const Icon(Icons.fingerprint_rounded),
            label: Text(_signing ? 'Signing request…' : 'Unlock to sign'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _signing ? null : () => Navigator.pop(context),
            child: const Text('Go back and review'),
          ),
        ],
      ),
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Icon(
            Icons.fingerprint_rounded,
            color: SignerColors.mint,
            size: 72,
          ),
        ),
        SignerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VISIBLE OUTPUTS',
                style: TextStyle(fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              Text(
                formatZec(widget.review.visibleOutputTotalZat),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Text(
                'Request ${widget.review.requestIdHex}',
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const QuietNotice(
          'Signing authorizes this request. Vizor still needs to receive the signatures and broadcast the transaction.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          QuietNotice(_error!, warning: true),
        ],
      ],
    ),
  );
}
