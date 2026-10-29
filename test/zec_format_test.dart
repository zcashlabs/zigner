import 'package:airgapped_zcash_signer/src/util/zec_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats zatoshis as ZEC without floating-point rounding', () {
    expect(formatZec(BigInt.zero), '0 ZEC');
    expect(formatZec(BigInt.from(1)), '0.00000001 ZEC');
    expect(formatZec(BigInt.from(12340000)), '0.1234 ZEC');
    expect(formatZec(BigInt.from(100000000)), '1 ZEC');
  });
}
