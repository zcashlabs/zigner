import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null || data['signedResponseUrParts'] is! List) {
      throw StateError(
        'The Android signing flow did not return a signature response.',
      );
    }
    final output = File('build/ci/signer-response.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    );
  },
);
