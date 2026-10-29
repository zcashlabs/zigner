import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SeedVault {
  const SeedVault();

  static const _mnemonicKey = 'zcash_testnet_mnemonic_v1';
  static const _storage = FlutterSecureStorage();

  Future<bool> get isProvisioned async =>
      (await _storage.read(key: _mnemonicKey)) != null;

  Future<String> provisionNew() async {
    final mnemonic = bip39.generateMnemonic(strength: 256);
    await importMnemonic(mnemonic);
    return mnemonic;
  }

  Future<void> importMnemonic(String mnemonic) async {
    final normalized = mnemonic
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .join(' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw const FormatException('Enter a valid BIP-39 recovery phrase.');
    }
    await _storage.write(key: _mnemonicKey, value: normalized);
  }

  Future<Uint8List> readSeed() async {
    final mnemonic = await _storage.read(key: _mnemonicKey);
    if (mnemonic == null) throw StateError('No signer wallet is provisioned.');
    return bip39.mnemonicToSeed(mnemonic);
  }

  Future<String> readMnemonicForBackup() async {
    final mnemonic = await _storage.read(key: _mnemonicKey);
    if (mnemonic == null) throw StateError('No signer wallet is provisioned.');
    return mnemonic;
  }

  Future<void> delete() => _storage.delete(key: _mnemonicKey);
}
