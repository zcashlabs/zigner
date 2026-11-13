import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security/seed_vault.dart';
import '../theme/signer_theme.dart';
import '../widgets/backup_quiz.dart';
import 'account_export_screen.dart';

enum _SetupStep {
  welcome,
  safety,
  choose,
  tips,
  words,
  verify,
  import,
  passphrase,
  protect,
  ready,
}

class ProvisionScreen extends StatefulWidget {
  const ProvisionScreen({
    super.key,
    required this.status,
    required this.onProvisioned,
    required this.onRetry,
  });
  final VaultStatus status;
  final VoidCallback onProvisioned, onRetry;
  @override
  State<ProvisionScreen> createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen>
    with WidgetsBindingObserver {
  static const _vault = SeedVault();
  final _phrase = TextEditingController();
  final _passphrase = TextEditingController();
  final _passphraseConfirmation = TextEditingController();
  _SetupStep _step = _SetupStep.welcome;
  RecoveryDraft? _draft;
  PhraseInspection? _inspection;
  Future<void>? _inspectionPending;
  Timer? _debounce;
  bool _busy = false,
      _written = false,
      _revealed = false,
      _usePassphrase = false,
      _verified = false;
  int _epoch = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phrase.addListener(_phraseChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _step != _SetupStep.ready) {
      _epoch++;
      // A credential Activity may pause Flutter. Native retains only that operation.
      if (!_busy) _reset();
    }
  }

  void _clearInputs() {
    _phrase.clear();
    _passphrase.clear();
    _passphraseConfirmation.clear();
  }

  void _reset() {
    _debounce?.cancel();
    _clearInputs();
    unawaited(_vault.discardDraft().catchError((Object _) {}));
    if (mounted) {
      setState(() {
        _draft = null;
        _inspection = null;
        _step = _SetupStep.choose;
        _error = null;
        _written = false;
        _revealed = false;
        _verified = false;
        _usePassphrase = false;
      });
    }
  }

  void _go(_SetupStep step) => setState(() {
    _step = step;
    _error = null;
  });
  void _phraseChanged() {
    _debounce?.cancel();
    if (mounted) setState(() => _inspection = null);
    if (_step == _SetupStep.import && !_busy) {
      _debounce = Timer(const Duration(milliseconds: 250), () {
        _inspectionPending ??= _inspect();
      });
    }
  }

  Future<void> _inspect() async {
    final text = _phrase.text;
    final epoch = _epoch;
    try {
      final info = await _vault.inspectPhrase(text);
      if (mounted &&
          text == _phrase.text &&
          epoch == _epoch &&
          _step == _SetupStep.import) {
        setState(() {
          _inspection = info;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && text == _phrase.text && epoch == _epoch) {
        setState(() => _error = vaultErrorMessage(e));
      }
    } finally {
      _inspectionPending = null;
      if (mounted &&
          text != _phrase.text &&
          _step == _SetupStep.import &&
          !_busy) {
        _phraseChanged();
      }
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    bool authenticating = false,
  }) async {
    if (_busy) return;
    final epoch = _epoch;
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _inspectionPending;
      if (!mounted || (!authenticating && epoch != _epoch)) return;
      await operation();
    } catch (e) {
      if (mounted) setState(() => _error = vaultErrorMessage(e));
    } finally {
      if (mounted && !authenticating && epoch != _epoch) _reset();
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validPassphrase() {
    if (_usePassphrase &&
        (_passphrase.text.isEmpty ||
            _passphrase.text != _passphraseConfirmation.text)) {
      setState(
        () => _error = 'Enter the same extra passphrase in both fields, or turn this option off.',
      );
      return false;
    }
    return true;
  }

  Future<void> _generate() async {
    if (!_validPassphrase()) return;
    final epoch = _epoch;
    await _run(() async {
      final draft = await _vault.generate(
        passphrase: _usePassphrase ? _passphrase.text : '',
      );
      _clearInputs();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _draft = draft;
        _step = _SetupStep.words;
        _revealed = false;
      });
    });
  }

  Future<void> _prepareImport() async {
    if (!_validPassphrase()) return;
    final epoch = _epoch;
    await _run(() async {
      await _vault.prepareImport(
        _phrase.text,
        passphrase: _usePassphrase ? _passphrase.text : '',
      );
      _clearInputs();
      if (mounted && epoch == _epoch) _go(_SetupStep.protect);
    });
  }

  Future<void> _save() => _run(() async {
    await _vault.save();
    _draft = null;
    _clearInputs();
    if (mounted) _go(_SetupStep.ready);
  }, authenticating: true);
  void _back() {
    if (_busy) return;
    switch (_step) {
      case _SetupStep.safety:
        _go(_SetupStep.welcome);
      case _SetupStep.choose:
        _go(_SetupStep.safety);
      case _SetupStep.passphrase:
        _go(_SetupStep.import);
        _phraseChanged();
      case _SetupStep.verify:
        _run(() async {
          await _vault.restartBackupCheck();
          if (mounted) {
            setState(() {
              _verified = false;
              _revealed = false;
              _step = _SetupStep.words;
            });
          }
        });
      default:
        _reset();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _phrase.removeListener(_phraseChanged);
    unawaited(_vault.discardDraft().catchError((Object _) {}));
    _draft = null;
    for (final c in [_phrase, _passphrase, _passphraseConfirmation]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Widget _primary(String text, VoidCallback? action, {IconData? icon}) =>
      FilledButton(
        onPressed: _busy ? null : action,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 21),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: Text(text)),
                ],
              ),
      );
  Widget _actions(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null) ...[
        QuietNotice(_error!, warning: true),
        const SizedBox(height: 12),
      ],
      ...children,
    ],
  );
  Widget _brand() => const Row(
    children: [
      Expanded(child: ZignerBrand()),
      SizedBox(width: 12),
      TestnetBadge(),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final blocked =
        !widget.status.ready ||
        (widget.status.hasSigner && !widget.status.hasLegacySigner);
    if (blocked) {
      return SignerPage(
        title: 'One thing to fix first.',
        description: 'Zigner needs a screen lock and authenticated hardware storage to protect your signer.',
        footer: _actions([
          _primary(
            'Open security settings',
            () => _run(_vault.openSecuritySettings),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onRetry,
            child: const Text('Check again'),
          ),
        ]),
        children: [
          QuietNotice(
            widget.status.error ?? 'Your stored signer could not be opened. Keep your offline recovery backup.',
            warning: true,
          ),
        ],
      );
    }
    if (widget.status.hasLegacySigner) {
      return SignerPage(
        header: _brand(),
        title: 'Keep your signer.\nUpgrade its protection.',
        description: 'Move your prototype signer into authenticated hardware storage without changing its recovery phrase.',
        footer: _actions([
          _primary(
            'Upgrade signer protection',
            () => _run(() async {
              await _vault.upgradeLegacy();
              if (mounted) widget.onProvisioned();
            }, authenticating: true),
          ),
        ]),
        children: const [
          QuietNotice(
            'Keep your recovery backup. Android will ask you to authenticate to save the protected copy, then again to verify it before the old copy is removed.',
          ),
        ],
      );
    }
    final progress = switch (_step) {
      _SetupStep.tips => 1,
      _SetupStep.words => 2,
      _SetupStep.verify => 3,
      _SetupStep.protect => 4,
      _ => null,
    };
    final (title, description) = switch (_step) {
      _SetupStep.welcome => (
        'Sign Zcash,\ncalmly and offline.',
        'Your keys stay on this phone. Your computer prepares a payment, you check it here, and you pass the signature back by QR code.',
      ),
      _SetupStep.safety => (
        'Let’s check this\nphone is ready.',
        'A few protections before your keys move in.',
      ),
      _SetupStep.choose => (
        'How would you\nlike to start?',
        'A new signer or a recovery phrase you already have. Both stay on this phone.',
      ),
      _SetupStep.tips => (
        'Grab a pen\nand paper.',
        'You’ll write down 24 words. They’re your way back in if this phone is lost or reset.',
      ),
      _SetupStep.words => (
        'Write down these\n24 words.',
        'Keep the numbers and words in order. Take your time; there’s no rush.',
      ),
      _SetupStep.verify => (
        _verified ? 'Your backup\nlooks right.' : 'Check your\npaper backup.',
        _verified
            ? 'All three words match. Now let’s protect your signer on this phone.'
            : 'Find each word on your paper, then choose it below.',
      ),
      _SetupStep.import => (
        'Bring your\nrecovery phrase.',
        'Enter your words in order, separated by spaces. Suggestions come from the word list inside Zigner.',
      ),
      _SetupStep.passphrase => (
        'Did you use an\nextra passphrase?',
        'This is an optional BIP-39 passphrase. It’s separate from your phone’s screen lock.',
      ),
      _SetupStep.protect => (
        'Lock your signer\nto this phone.',
        'Android will ask you to unlock before encrypting your signer. Your recovery words aren’t saved as a text file.',
      ),
      _SetupStep.ready => (
        'Your signer\nis ready.',
        'Your keys are protected on this phone. Connect to Vizor when you’re ready to make a testnet payment.',
      ),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            _step != _SetupStep.welcome &&
            _step != _SetupStep.ready) {
          _back();
        }
      },
      child: SignerPage(
        header: progress != null
            ? SetupProgress(step: progress, onBack: _back)
            : (_step == _SetupStep.welcome || _step == _SetupStep.ready)
            ? _brand()
            : null,
        onBack: _back,
        title: title,
        description: description,
        footer: _actions(_footer()),
        children: _contents(),
      ),
    );
  }

  List<Widget> _contents() => switch (_step) {
    _SetupStep.welcome => [
      const SizedBox(height: 12),
      SignerCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: _diagram(Icons.laptop_rounded, 'Vizor')),
            const Expanded(
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 32,
                    color: SignerColors.mint,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'QR ONLY',
                    style: TextStyle(fontSize: 10, letterSpacing: 1.2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _diagram(Icons.phone_android_rounded, 'This phone'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      const QuietNotice(
        'Early testnet prototype. Don’t use it for real funds.',
        warning: true,
      ),
    ],
    _SetupStep.safety => [
      SignerCard(
        child: Column(
          children: [
            const InfoRow(
              icon: Icons.lock_outline_rounded,
              title: 'Screen lock is set',
              detail: 'Android will ask for your fingerprint or device screen lock.',
            ),
            const Divider(),
            InfoRow(
              icon: Icons.memory_rounded,
              title: widget.status.protectionLabel,
              detail: 'The encryption key is protected by verified hardware.',
            ),
            const Divider(),
            InfoRow(
              icon: widget.status.internetPermission
                  ? Icons.developer_mode_rounded
                  : Icons.wifi_off_rounded,
              title: widget.status.internetPermission
                  ? 'Development connection enabled'
                  : 'No app network permission',
              detail: widget.status.internetPermission
                  ? 'This debug build allows Flutter development tools. Disconnect USB and use a release build for offline use.'
                  : 'This build exchanges requests and signatures by QR.',
              color: widget.status.internetPermission
                  ? SignerColors.gold
                  : SignerColors.mint,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const QuietNotice(
        'For an offline signing session, turn on airplane mode and turn off Wi-Fi and Bluetooth.',
      ),
    ],
    _SetupStep.choose => [
      _choice(
        Icons.add_rounded,
        'Create a new signer',
        'A fresh set of 24 recovery words.\nYou’ll need a pen and about five minutes.',
        () => _go(_SetupStep.tips),
        recommended: true,
      ),
      const SizedBox(height: 16),
      _choice(
        Icons.key_rounded,
        'I have a recovery phrase',
        'Restore from 12, 15, 18, 21, or 24 English recovery words.',
        () => _go(_SetupStep.import),
      ),
      const SizedBox(height: 24),
      const QuietNotice(
        'Keep your paper backup offline. Anyone with your recovery words can control your signer.',
      ),
    ],
    _SetupStep.tips => [
      const InfoRow(
        icon: Icons.edit_outlined,
        title: 'Write them down by hand',
        detail: 'Use paper. Keep every word in its numbered position.',
      ),
      const InfoRow(
        icon: Icons.no_photography_outlined,
        title: 'Skip photos and screenshots',
        detail: 'Photos can end up in cloud backups without you noticing.',
      ),
      const InfoRow(
        icon: Icons.visibility_off_outlined,
        title: 'Find a private spot',
        detail: 'Make sure no one can see your screen or your paper.',
      ),
      const SizedBox(height: 16),
      _passphraseFields(creating: true),
    ],
    _SetupStep.words => [
      if (!_revealed)
        SignerCard(
          child: Column(
            children: [
              const Icon(
                Icons.visibility_off_outlined,
                size: 40,
                color: SignerColors.mint,
              ),
              const SizedBox(height: 16),
              const Text('Make sure you’re somewhere private.'),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal recovery words'),
              ),
            ],
          ),
        )
      else ...[
        SignerCard(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (var i = 0; i < _draft!.words.length; i++)
                  SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}'.padLeft(2, '0'),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _draft!.words[i],
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              color: SignerColors.text,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _revealed = false),
          icon: const Icon(Icons.visibility_off_outlined, size: 18),
          label: const Text('Hide words'),
        ),
      ],
      const SizedBox(height: 16),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'I wrote down all 24 words in order.',
          style: TextStyle(fontSize: 14),
        ),
        value: _written,
        onChanged: _revealed
            ? (v) => setState(() => _written = v ?? false)
            : null,
      ),
      const QuietNotice(
        'Leaving the app discards this unsaved setup. Your recovery words are never backed up to the cloud.',
      ),
    ],
    _SetupStep.verify =>
      _verified
          ? [
              const Padding(
                padding: EdgeInsets.all(32),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: SignerColors.mint,
                  size: 72,
                ),
              ),
              const QuietNotice(
                'Keep your paper somewhere safe. You’ll need it to recover your signer on another device.',
              ),
            ]
          : [
              BackupQuiz(
                questions: _draft!.questions,
                onComplete: () => setState(() => _verified = true),
              ),
            ],
    _SetupStep.import => [
      _secretField(_phrase, 'Recovery phrase', multiline: true),
      const SizedBox(height: 12),
      Text(
        _inspection == null
            ? '12, 15, 18, 21, or 24 words · English BIP-39'
            : '${_inspection!.count} words · ${_inspection!.valid ? 'Checksum looks right' : 'Keep entering or check your words'}',
        style: TextStyle(
          fontSize: 12,
          color: _inspection?.valid == true
              ? SignerColors.mint
              : SignerColors.textMuted,
        ),
      ),
      if (_inspection?.suggestions.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final word in _inspection!.suggestions)
              ActionChip(
                label: Text(
                  word,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 12,
                  ),
                ),
                onPressed: () {
                  final value = _phrase.text.replaceFirst(
                    RegExp(r'\S+$'),
                    '$word ',
                  );
                  _phrase.value = TextEditingValue(
                    text: value,
                    selection: TextSelection.collapsed(offset: value.length),
                  );
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      const QuietNotice(
        'Type only on this phone. Zigner turns off keyboard suggestions and learning for this field.',
      ),
    ],
    _SetupStep.passphrase => [
      QuietNotice(
        '${_inspection?.count ?? ''} recovery words · checksum checked',
      ),
      const SizedBox(height: 20),
      _passphraseFields(creating: false),
    ],
    _SetupStep.protect => [
      const Padding(
        padding: EdgeInsets.all(20),
        child: Icon(Icons.memory_rounded, color: SignerColors.mint, size: 72),
      ),
      SignerCard(
        child: Column(
          children: [
            InfoRow(
              icon: Icons.security_outlined,
              title: widget.status.protectionLabel,
              detail: 'Protects the encryption key. Recovery and signing material briefly enters app memory when needed.',
            ),
            const InfoRow(
              icon: Icons.lock_outline,
              title: 'Encrypted on this device',
              detail: 'AES-256-GCM storage, with fresh Android authentication for each unlock.',
            ),
            const InfoRow(
              icon: Icons.cloud_off_outlined,
              title: 'No cloud backup',
              detail: 'Your paper is your recovery backup. Zigner excludes the vault from Android backups.',
            ),
          ],
        ),
      ),
    ],
    _SetupStep.ready => [
      const Padding(
        padding: EdgeInsets.all(24),
        child: Icon(
          Icons.check_circle_outline_rounded,
          size: 80,
          color: SignerColors.mint,
        ),
      ),
      SignerCard(
        child: InfoRow(
          icon: Icons.key_outlined,
          title: 'Main account',
          detail: 'Zcash Testnet · ${widget.status.protectionLabel}',
        ),
      ),
    ],
  };
  List<Widget> _footer() => switch (_step) {
    _SetupStep.welcome => [
      _primary(
        'Get started',
        () => _go(_SetupStep.safety),
        icon: Icons.arrow_forward_rounded,
      ),
    ],
    _SetupStep.safety => [_primary('Continue', () => _go(_SetupStep.choose))],
    _SetupStep.choose => [],
    _SetupStep.tips => [_primary('I’m ready, show my words', _generate)],
    _SetupStep.words => [
      _primary(
        'Check my backup',
        _written
            ? () {
                setState(() {
                  _revealed = false;
                  _step = _SetupStep.verify;
                });
              }
            : null,
      ),
    ],
    _SetupStep.verify =>
      _verified
          ? [
              _primary('Continue', () {
                _draft = null;
                _go(_SetupStep.protect);
              }),
            ]
          : [
              if (kDebugMode)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await _vault.skipBackupCheckForDebug();
                          if (mounted) {
                            _draft = null;
                            _go(_SetupStep.protect);
                          }
                        }),
                  child: const Text('Skip backup check · debug only'),
                ),
              TextButton(
                onPressed: _busy ? null : _back,
                child: const Text('See my words again'),
              ),
            ],
    _SetupStep.import => [
      _primary(
        'Continue',
        _inspection?.valid == true ? () => _go(_SetupStep.passphrase) : null,
      ),
    ],
    _SetupStep.passphrase => [
      _primary(
        _usePassphrase
            ? 'Continue with passphrase'
            : 'Continue without passphrase',
        _prepareImport,
      ),
    ],
    _SetupStep.protect => [
      _primary('Unlock to protect', _save, icon: Icons.fingerprint_rounded),
    ],
    _SetupStep.ready => [
      _primary('Connect to Vizor', () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const AccountExportScreen()),
        );
        if (mounted) widget.onProvisioned();
      }, icon: Icons.qr_code_2_rounded),
      const SizedBox(height: 8),
      TextButton(
        onPressed: widget.onProvisioned,
        child: const Text('I’ll do this later'),
      ),
    ],
  };
  Widget _diagram(IconData icon, String text) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: SignerColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 32, color: SignerColors.mint),
      ),
      const SizedBox(height: 12),
      Text(
        text,
        style: const TextStyle(fontSize: 13, color: SignerColors.text),
      ),
    ],
  );
  Widget _choice(
    IconData icon,
    String title,
    String detail,
    VoidCallback action, {
    bool recommended = false,
  }) => Material(
    color: SignerColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: recommended
            ? SignerColors.mint.withValues(alpha: .5)
            : SignerColors.border,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: SignerColors.mint, size: 28),
                const Spacer(),
                if (recommended)
                  const Text(
                    'RECOMMENDED',
                    style: TextStyle(
                      color: SignerColors.mint,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(detail, style: const TextStyle(fontSize: 14, height: 1.6)),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: SignerColors.mint,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _passphraseFields({required bool creating}) => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          creating ? 'Add an extra passphrase' : 'I used an extra passphrase',
          style: const TextStyle(fontSize: 15),
        ),
        subtitle: const Text(
          'Optional · advanced',
          style: TextStyle(fontSize: 12),
        ),
        value: _usePassphrase,
        onChanged: _busy
            ? null
            : (v) => setState(() {
                _usePassphrase = v;
                _passphrase.clear();
                _passphraseConfirmation.clear();
              }),
      ),
      if (_usePassphrase) ...[
        const SizedBox(height: 12),
        _secretField(_passphrase, 'Extra passphrase', obscure: true),
        const SizedBox(height: 12),
        _secretField(
          _passphraseConfirmation,
          'Confirm extra passphrase',
          obscure: true,
        ),
        const SizedBox(height: 16),
        const QuietNotice(
          'Every passphrase opens a different signer. There’s no wrong-passphrase warning or reset. Back it up separately from your words.',
          warning: true,
        ),
      ],
    ],
  );
  Widget _secretField(
    TextEditingController controller,
    String label, {
    bool multiline = false,
    bool obscure = false,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    minLines: multiline ? 5 : 1,
    maxLines: multiline ? 7 : 1,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    autofillHints: null,
    enableInteractiveSelection: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    keyboardType: TextInputType.visiblePassword,
    textCapitalization: TextCapitalization.none,
    maxLength: multiline ? 1024 : 256,
    style: const TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 14,
      height: 1.8,
    ),
    inputFormatters: multiline
        ? null
        : [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      counterText: '',
    ),
  );
}
