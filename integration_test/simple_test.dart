import 'package:airgapped_zcash_signer/src/app.dart';
import 'package:airgapped_zcash_signer/src/rust/api/simple.dart';
import 'package:airgapped_zcash_signer/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets('renders the offline signer and calls the Rust core', (
    tester,
  ) async {
    final review = inspectDemoRequest(
      payload: '''{"network":"testnet","transaction_kind":"shielded","recipient":"utest1prototypeaddress0000000000000000000000000000000000","amount_zat":1,"fee_zat":0}''',
    );

    expect(review.network, 'testnet');
    expect(review.amountZat, BigInt.one);

    await tester.pumpWidget(const SignerApp());
    expect(find.text('Zcash testnet prototype'), findsOneWidget);
    expect(
      find.text('PROTOTYPE ONLY · TESTNET · NOT FOR FUNDS'),
      findsOneWidget,
    );
  });
}
