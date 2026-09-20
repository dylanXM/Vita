const vitaSubscriptionProductIds = <String>{
  'vita.plus.monthly',
  'vita.plus.yearly',
  'vita.premium.monthly',
  'vita.premium.yearly',
};

const vitaCoinProductIds = <String, int>{
  'vita.coins.100': 100,
  'vita.coins.500': 500,
  'vita.coins.1200': 1200,
};

bool isSubscriptionProduct(String packageIdentifier, String productIdentifier) {
  final packageId = packageIdentifier.toLowerCase();
  final productId = productIdentifier.toLowerCase();
  return vitaSubscriptionProductIds.contains(productId) ||
      packageId.contains('plus') ||
      packageId.contains('premium');
}

bool isPremiumProduct(String packageIdentifier, String productIdentifier) {
  return packageIdentifier.toLowerCase().contains('premium') ||
      productIdentifier.toLowerCase().startsWith('vita.premium.');
}

bool isCoinProduct(String packageIdentifier, String productIdentifier) {
  final packageId = packageIdentifier.toLowerCase();
  final productId = productIdentifier.toLowerCase();
  return vitaCoinProductIds.containsKey(productId) ||
      packageId.startsWith('credits_') ||
      packageId.startsWith('coins_');
}
