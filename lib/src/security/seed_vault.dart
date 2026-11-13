import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VaultStatus {
  const VaultStatus({
    required this.hasSigner,
    required this.ready,
    required this.protection,
    this.hasLegacySigner = false,
    this.error,
    this.backupChecked = false,
    this.internetPermission = true,
  });
  final bool hasSigner;
  final bool ready;
  final String protection;
  final bool hasLegacySigner;
  final String? error;
  final bool backupChecked, internetPermission;
  String get protectionLabel => switch (protection) {
    'strongbox' => 'StrongBox secure element',
    'tee' => 'Hardware-backed Android Keystore',
    _ => 'Protection unavailable',
  };
}

class BackupQuestion {
  const BackupQuestion({required this.index, required this.choices});
  final int index;
  final List<String> choices;
  factory BackupQuestion.fromMap(Map<dynamic, dynamic> data) => BackupQuestion(
    index: data['index'] as int,
    choices: List<String>.from(data['choices'] as List),
  );
}

class PhraseInspection {
  const PhraseInspection({
    required this.count,
    required this.valid,
    required this.suggestions,
  });
  final int count;
  final bool valid;
  final List<String> suggestions;
}

class RecoveryDraft {
  const RecoveryDraft({
    required this.words,
    required this.challenge,
    required this.questions,
  });
  final List<String> words;
  final List<int> challenge;
  final List<BackupQuestion> questions;
}

/// Native Android owns generation, encrypted storage and authenticated unlocking.
/// The old storage plugin is used only to preserve/upgrade prototype signers.
class SeedVault {
  const SeedVault();
  static const channel = MethodChannel('org.zcash.zigner/seed_vault');
  // Session UI only; every native encrypt/decrypt still requires a fresh CryptoObject.
  static bool authenticationInProgress = false;
  static final authenticationCompleted =
      ValueNotifier<({int sequence, bool succeeded})>((
        sequence: 0,
        succeeded: false,
      ));
  static Future<T> _authenticate<T>(Future<T> Function() action) async {
    authenticationInProgress = true;
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      authenticationInProgress = false;
      authenticationCompleted.value = (
        sequence: authenticationCompleted.value.sequence + 1,
        succeeded: succeeded,
      );
    }
  }

  // Route disposal and device-status refresh can overlap. Serialize channel calls
  // so an idle-draft cleanup cannot collide with a CryptoObject operation.
  static Future<void>? _tail;
  static Future<T> _serial<T>(Future<T> Function() action) {
    final previous = _tail;
    final result = previous == null ? action() : previous.then((_) => action());
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return result;
  }

  static Future<T?> _invoke<T>(String method, [dynamic arguments]) =>
      _serial(() => channel.invokeMethod<T>(method, arguments));
  static Future<Map<String, dynamic>?> _map(
    String method, [
    dynamic arguments,
  ]) => _serial(
    () => channel.invokeMapMethod<String, dynamic>(method, arguments),
  );
  static const _legacyKey = 'zcash_testnet_mnemonic_v1';
  static const _legacy = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
  );

  Future<VaultStatus> status() async {
    final data = await _map('status');
    if (data == null) {
      throw StateError('Android seed protection is unavailable.');
    }
    return VaultStatus(
      hasSigner: data['hasSigner'] == true,
      ready: data['ready'] == true,
      protection: data['protection'] as String? ?? 'unavailable',
      error: data['error'] as String?,
      backupChecked: data['backupChecked'] == true,
      internetPermission: data['internetPermission'] != false,
      // Native inspects ciphertext metadata without initializing the old plugin.
      hasLegacySigner: data['hasLegacySigner'] == true,
    );
  }

  Future<RecoveryDraft> generate({String passphrase = ''}) async {
    final data = await _map('generate', {'passphrase': passphrase});
    return RecoveryDraft(
      words: List<String>.from(data!['words'] as List),
      challenge: List<int>.from(data['challenge'] as List),
      questions: (data['questions'] as List)
          .map((q) => BackupQuestion.fromMap(q as Map))
          .toList(),
    );
  }

  Future<void> prepareImport(String mnemonic, {String passphrase = ''}) =>
      _invoke<void>('prepareImport', {
        'mnemonic': mnemonic,
        'passphrase': passphrase,
      });
  Future<void> confirmBackup(List<String> answers) =>
      _invoke<void>('confirmBackup', {'answers': answers});
  Future<void> save() => _authenticate(() => _invoke<void>('save'));
  Future<void> unlock() => _authenticate(() => _invoke<void>('unlock'));
  Future<void> erase(String confirmation) => _authenticate(
    () => _invoke<void>('erase', {'confirmation': confirmation}),
  );
  Future<void> openSecuritySettings() => _invoke<void>('openSecuritySettings');
  Future<void> restartBackupCheck() => _invoke<void>('restartBackupCheck');
  Future<void> skipBackupCheckForDebug() {
    if (!kDebugMode) {
      throw StateError('Skipping the backup check requires a debug build.');
    }
    return _invoke<void>('skipBackupCheckForDebug');
  }

  Future<({bool correct, bool complete})> checkBackupWord(
    int question,
    String word,
  ) async {
    final data = await _map('checkBackupWord', {
      'question': question,
      'word': word,
    });
    return (
      correct: data?['correct'] == true,
      complete: data?['complete'] == true,
    );
  }

  Future<List<BackupQuestion>> practiceBackup() => _authenticate(() async {
    final data = await _map('practiceBackup');
    return (data!['questions'] as List)
        .map((q) => BackupQuestion.fromMap(q as Map))
        .toList();
  });
  Future<PhraseInspection> inspectPhrase(String mnemonic) async {
    final data = await _map('inspectPhrase', {'mnemonic': mnemonic});
    return PhraseInspection(
      count: data!['count'] as int,
      valid: data['valid'] == true,
      suggestions: List<String>.from(data['suggestions'] as List),
    );
  }

  Future<void> discardDraft() => _invoke<void>('discardDraft');

  Future<Uint8List> readSeed() async {
    final delivered = await _authenticate(() => _invoke<Uint8List>('readSeed'));
    if (delivered == null) {
      throw StateError('Android could not unlock the signer.');
    }
    // Android platform messages can expose read-only typed-data views. Give
    // callers an owned, writable buffer that can be cleared in their finally
    // blocks. The codec's managed view cannot be reliably erased from Dart.
    final seed = Uint8List.fromList(delivered);
    if (seed.length != 64) {
      seed.fillRange(0, seed.length, 0);
      throw StateError('Android could not unlock the signer.');
    }
    // Only retire the old copy after an authenticated read of the new vault.
    try {
      final state = await _map('status');
      if (state?['hasLegacySigner'] == true) {
        await _legacy.delete(key: _legacyKey);
      }
    } catch (_) {
      seed.fillRange(0, seed.length, 0);
      throw StateError(
        'The old signer copy could not be removed. Retry the upgrade.',
      );
    }
    return seed;
  }

  Future<void> upgradeLegacy() async {
    // Resume safely if saving succeeded but the second authentication was cancelled.
    final state = await _map('status');
    if (state?['hasSigner'] != true) {
      final phrase = await _legacy.read(key: _legacyKey);
      if (phrase == null) throw StateError('No prototype signer was found.');
      await prepareImport(phrase);
      await save();
    }
    final seed = await readSeed();
    seed.fillRange(0, seed.length, 0);
  }
}

String vaultErrorMessage(Object error) => switch (error) {
  PlatformException(:final message) =>
    message ?? 'Android seed protection is unavailable.',
  MissingPluginException() =>
    'Seed protection requires the Android app on a supported device.',
  _ => 'Could not complete the operation. Your stored signer has not been replaced.',
};
