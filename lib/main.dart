import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final name in ['manrope', 'inter', 'jetbrainsmono']) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$name-OFL.txt'));
    }
  });
  await RustLib.init();
  runApp(const SignerApp());
}
