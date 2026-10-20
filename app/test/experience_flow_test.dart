import 'package:flutter_test/flutter_test.dart';
import 'package:vita/core/api_client.dart';
import 'package:vita/features/chat/experience_flow.dart';

void main() {
  test('unknown settlement and in-flight purchases retain the original request',
      () {
    expect(experienceNeedsRecovery(ApiException('timeout')), isTrue);
    expect(
        experienceNeedsRecovery(ApiException('pending',
            code: 'spend_in_progress', statusCode: 409)),
        isTrue);
    expect(
        experienceNeedsRecovery(ApiException('refund unknown',
            code: 'refund_unconfirmed', statusCode: 500)),
        isTrue);
  });
  test('confirmed refunds and changed prices allow fresh confirmation', () {
    expect(
        experienceNeedsRecovery(
            ApiException('refunded', code: 'spend_refunded', statusCode: 409)),
        isFalse);
    expect(
        experienceNeedsRecovery(ApiException('price changed',
            code: 'experience_price_changed', statusCode: 409)),
        isFalse);
  });
}
