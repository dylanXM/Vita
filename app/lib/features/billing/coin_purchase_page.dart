import 'package:flutter/material.dart';

import 'credits_page.dart';

/// A dedicated coin store using the wallet's existing purchase flow.
class CoinPurchasePage extends StatelessWidget {
  const CoinPurchasePage({super.key});

  @override
  Widget build(BuildContext context) => const CreditsPage(purchaseOnly: true);
}
