import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const SignerApp());
}
