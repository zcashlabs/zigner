import 'package:airgapped_zcash_signer/src/security/seed_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const legacy = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const vault = SeedVault();
  late List<String> calls;
  late bool hasNativeSigner;
  late bool cancelUnlock;
  setUp(() {
    calls = [];
    hasNativeSigner = false;
    cancelUnlock = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(legacy, (call) async {
      calls.add('legacy.${call.method}');
      return switch (call.method) {
        'containsKey' => true,
        'read' => 'public test phrase',
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(SeedVault.channel, (call) async {
      calls.add('vault.${call.method}');
      switch (call.method) {
        case 'status':
          return {
            'hasSigner': hasNativeSigner,
            'ready': true,
            'protection': 'strongbox',
            'hasLegacySigner': true,
          };
        case 'save':
          hasNativeSigner = true;
          return null;
        case 'readSeed':
          if (cancelUnlock) throw PlatformException(code: 'AUTH_CANCELLED');
          return Uint8List(64);
        default:
          return null;
      }
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(legacy, null);
    messenger.setMockMethodCallHandler(SeedVault.channel, null);
  });

  test(
    'startup checks presence without decrypting the existing phrase',
    () async {
      expect((await vault.status()).hasLegacySigner, true);
      expect(calls, ['vault.status']);
    },
  );
  test('migration retains old copy when new vault authentication is cancelled and resumes safely', () async {
    cancelUnlock = true;
    await expectLater(vault.upgradeLegacy(), throwsA(isA<PlatformException>()));
    expect(hasNativeSigner, true);
    expect(calls.contains('legacy.delete'), false);
    calls.clear();
    cancelUnlock = false;
    await vault.upgradeLegacy();
    expect(calls, [
      'vault.status',
      'vault.readSeed',
      'vault.status',
      'legacy.delete',
    ]);
  });
  test('migration removes old copy only after saving and authenticated verification', () async {
    await vault.upgradeLegacy();
    expect(calls, [
      'vault.status',
      'legacy.read',
      'vault.prepareImport',
      'vault.save',
      'vault.readSeed',
      'vault.status',
      'legacy.delete',
    ]);
  });

  test('Android read-only message bytes become an owned seed that callers can wipe', () async {
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final expected = List<int>.generate(64, (i) => i);
    ByteData readOnlyEnvelope(Object value) {
      final envelope = codec.encodeSuccessEnvelope(value);
      return ByteData.sublistView(
        Uint8List.sublistView(envelope).asUnmodifiableView(),
      );
    }

    messenger.setMockMessageHandler(SeedVault.channel.name, (message) async {
      final method = codec.decodeMethodCall(message).method;
      return readOnlyEnvelope(
        method == 'readSeed'
            ? Uint8List.fromList(expected)
            : {'hasSigner': true, 'hasLegacySigner': false},
      );
    });
    final platformView = codec.decodeEnvelope(
      readOnlyEnvelope(Uint8List.fromList(expected)),
    ) as Uint8List;
    expect(
      () => platformView.fillRange(0, platformView.length, 0),
      throwsUnsupportedError,
    );
    final seed = await vault.readSeed();
    expect(seed, orderedEquals(expected));
    seed.fillRange(0, seed.length, 0);
    expect(seed, everyElement(0));
    expect(platformView, orderedEquals(expected));
  });
}
