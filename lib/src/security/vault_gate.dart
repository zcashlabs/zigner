import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/provision_screen.dart';
import '../theme/signer_theme.dart';
import 'seed_vault.dart';

class VaultGate extends StatefulWidget {
  const VaultGate({super.key});
  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> with WidgetsBindingObserver {
  Future<VaultStatus> _status = const SeedVault().status();
  bool _unlocked = false;
  bool _backgroundDuringAuthentication = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SeedVault.authenticationCompleted.addListener(_authenticationFinished);
  }

  @override
  void dispose() {
    SeedVault.authenticationCompleted.removeListener(_authenticationFinished);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _unlocked) {
      if (SeedVault.authenticationInProgress) {
        // A system credential Activity may pause Flutter. Keep its route until
        // it completes, but don't retain the session if that unlock is cancelled.
        _backgroundDuringAuthentication = true;
      } else {
        _lock();
      }
    }
  }

  void _authenticationFinished() {
    if (!_backgroundDuringAuthentication) return;
    _backgroundDuringAuthentication = false;
    if (!SeedVault.authenticationCompleted.value.succeeded) _lock();
  }

  void _lock() {
    if (!mounted || !_unlocked) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _unlocked = false);
  }

  void _refresh({bool provisioned = false}) => setState(() {
    _unlocked = provisioned;
    _status = const SeedVault().status();
  });
  void _erased() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VaultStatus>(
    future: _status,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SignerPage(
          title: 'Couldn’t open the vault.',
          footer: FilledButton(
            onPressed: _refresh,
            child: const Text('Try again'),
          ),
          children: [
            QuietNotice(vaultErrorMessage(snapshot.error!), warning: true),
          ],
        );
      }
      final status = snapshot.data;
      if (status == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (status.hasSigner && status.ready && !status.hasLegacySigner) {
        if (!_unlocked) {
          return UnlockScreen(
            onUnlocked: () => setState(() => _unlocked = true),
          );
        }
        return HomeScreen(
          vaultStatus: status,
          onLock: _lock,
          onErased: _erased,
        );
      }
      return ProvisionScreen(
        status: status,
        onProvisioned: () => _refresh(provisioned: true),
        onRetry: _refresh,
      );
    },
  );
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await const SeedVault().unlock();
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) setState(() => _error = vaultErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SignerPage(
    header: const Row(
      children: [
        Expanded(child: ZignerBrand()),
        SizedBox(width: 12),
        TestnetBadge(),
      ],
    ),
    title: 'Welcome back.',
    description: 'Your signer is right here, protected on this phone.',
    footer: FilledButton.icon(
      onPressed: _busy ? null : _unlock,
      icon: const Icon(Icons.fingerprint_rounded),
      label: Text(_busy ? 'Waiting for Android…' : 'Unlock to open signer'),
    ),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Icon(
          Icons.fingerprint_rounded,
          size: 88,
          color: SignerColors.mint,
        ),
      ),
      const QuietNotice(
        'Use your fingerprint or device screen lock. Zigner asks again before signing or showing account data.',
      ),
      if (_error != null) ...[
        const SizedBox(height: 20),
        QuietNotice(_error!, warning: true),
      ],
    ],
  );
}

/// Removes app content from rendering and accessibility while Android is inactive.
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({super.key, required this.child});
  final Widget child;
  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  bool _hidden = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _hidden = state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(offstage: _hidden, child: widget.child),
      if (_hidden)
        const ColoredBox(
          color: SignerColors.background,
          child: Center(child: Icon(Icons.lock_outline, size: 40)),
        ),
    ],
  );
}
