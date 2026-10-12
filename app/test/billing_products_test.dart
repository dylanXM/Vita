import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/billing/billing_products.dart';

void main() {
  test('recognizes the configured subscription product IDs', () {
    expect(isSubscriptionProduct(r'$rc_monthly', 'vita.plus.monthly'), isTrue);
    expect(isSubscriptionProduct(r'$rc_annual', 'vita.premium.yearly'), isTrue);
    expect(isSubscriptionProduct('coins_500', 'vita.coins.500'), isFalse);
  });

  test('recognizes premium from the store product ID', () {
    expect(isPremiumProduct(r'$rc_monthly', 'vita.premium.monthly'), isTrue);
    expect(isPremiumProduct(r'$rc_monthly', 'vita.plus.monthly'), isFalse);
  });

  test('recognizes configured coin product IDs', () {
    expect(isCoinProduct('coins_100', 'vita.coins.100'), isTrue);
    expect(isCoinProduct('coins_500', 'vita.coins.500'), isTrue);
    expect(isCoinProduct('coins_1000', 'vita.coins.1000'), isTrue);
    expect(isCoinProduct('coin_pack', 'vita.coins.1200'), isTrue);
    expect(isCoinProduct('coins_500', 'vita.unknown'), isFalse);
    expect(isCoinProduct(r'$rc_monthly', 'vita.plus.monthly'), isFalse);
  });
}
