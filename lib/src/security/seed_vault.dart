import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum WalletStatus { empty, backupPending, ready }

typedef _Wallet = ({String mnemonic, bool backupConfirmed});

class SeedVault {
  const SeedVault([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false),
    ),
  ]);

  static const _legacyMnemonicKey = 'zcash_testnet_mnemonic_v1';
  static const _walletKey = 'zcash_testnet_wallet_v1';
  static Future<void>? _pending;
  final FlutterSecureStorage _storage;

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _pending;
    final gate = Completer<void>();
    _pending = gate.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_pending, gate.future)) _pending = null;
      gate.complete();
    }
  }

  Future<_Wallet?> _readWallet() async {
    final stored = await _storage.read(key: _walletKey);
    if (stored != null) {
      try {
        if (jsonDecode(stored) case {
          'mnemonic': final String mnemonic,
          'backupConfirmed': final bool confirmed,
        }) {
          if (bip39.validateMnemonic(mnemonic)) {
            return (mnemonic: mnemonic, backupConfirmed: confirmed);
          }
        }
      } on FormatException {
        // Keep recovery phrases out of JSON parsing errors.
      }
      throw StateError('Stored wallet could not be read.');
    }
    final legacy = await _storage.read(key: _legacyMnemonicKey);
    if (legacy == null) return null;
    if (!bip39.validateMnemonic(legacy)) {
      throw StateError('Stored wallet could not be read.');
    }
    return (mnemonic: legacy, backupConfirmed: false);
  }

  Future<void> _save(_Wallet wallet) => _storage.write(
    key: _walletKey,
    value: jsonEncode({
      'mnemonic': wallet.mnemonic,
      'backupConfirmed': wallet.backupConfirmed,
    }),
  );

  Future<WalletStatus> get status => _serialized(() async {
    final wallet = await _readWallet();
    if (wallet == null) return WalletStatus.empty;
    return wallet.backupConfirmed
        ? WalletStatus.ready
        : WalletStatus.backupPending;
  });

  Future<bool> get isProvisioned async => await status == WalletStatus.ready;

  Future<String> provisionNew() => _serialized(() async {
    final wallet = await _readWallet();
    if (wallet != null) {
      if (wallet.backupConfirmed) {
        throw StateError('A wallet is already set up.');
      }
      return wallet.mnemonic;
    }
    final mnemonic = bip39.generateMnemonic(strength: 256);
    await _save((mnemonic: mnemonic, backupConfirmed: false));
    return mnemonic;
  });

  Future<void> confirmBackup() => _serialized(() async {
    final wallet = await _readWallet();
    if (wallet == null) throw StateError('No signer wallet is provisioned.');
    if (!wallet.backupConfirmed) {
      await _save((mnemonic: wallet.mnemonic, backupConfirmed: true));
    }
  });

  Future<void> importMnemonic(String mnemonic) async {
    final normalized = mnemonic
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .join(' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw const FormatException('Enter a valid BIP-39 recovery phrase.');
    }
    await _serialized(() async {
      if (await _readWallet() != null) {
        throw StateError('A wallet already exists.');
      }
      await _save((mnemonic: normalized, backupConfirmed: true));
    });
  }

  Future<Uint8List> readSeed() => _serialized(() async {
    final wallet = await _readWallet();
    if (wallet == null) throw StateError('No signer wallet is provisioned.');
    if (!wallet.backupConfirmed) {
      throw StateError(
        'Confirm your recovery phrase backup before continuing.',
      );
    }
    return bip39.mnemonicToSeed(wallet.mnemonic);
  });

  Future<String> readMnemonicForBackup() => _serialized(() async {
    final wallet = await _readWallet();
    if (wallet == null) throw StateError('No signer wallet is provisioned.');
    return wallet.mnemonic;
  });

  Future<void> delete() => _serialized(() async {
    await _storage.delete(key: _legacyMnemonicKey);
    await _storage.delete(key: _walletKey);
  });
}
