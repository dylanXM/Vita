import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';

/// Billing state: RevenueCat (mobile subscriptions + credit packs), Stripe
/// (web/admin side) and the server-side credit balance / entitlement sync.
class BillingController extends GetxController {
  static BillingController get to => Get.find();

  final rcReady = false.obs;
  final busy = false.obs;

  final balance = 0.obs;
  final transactions = <Map<String, dynamic>>[].obs;

  final subscription = Rxn<Map<String, dynamic>>();
  final entitlements = <String>[].obs;
  final offerings = Rxn<Offerings>();

  @override
  void onInit() {
    super.onInit();
    init();
  }

  Future<void> init() async {
    if (revenueCatApiKey.isNotEmpty) {
      try {
        await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
        Purchases.addCustomerInfoUpdateListener((_) {
          refreshSubscription();
          refreshCredits();
        });
        rcReady.value = true;
        offerings.value = await Purchases.getOfferings();
      } catch (_) {
        rcReady.value = false;
      }
    }
    await refreshSubscription();
    await refreshCredits();
  }

  Future<void> refreshCredits() async {
    try {
      final data = await ApiClient.instance.get('/v1/me/credits');
      balance.value = (data['balance'] as num?)?.toInt() ?? 0;
      transactions.assignAll(
        (data['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (_) {
      // server unreachable — keep last known values
    }
  }

  Future<void> refreshSubscription() async {
    try {
      final data = await ApiClient.instance.get('/v1/me/subscription');
      subscription.value =
          data['subscription'] == null ? null : Map<String, dynamic>.from(data['subscription'] as Map);
      entitlements.assignAll(List<String>.from(data['entitlements'] as List? ?? []));
    } catch (_) {
      // keep last known values
    }
  }

  bool get isSubscribed => entitlements.isNotEmpty;

  /// Subscribes to a RevenueCat package (Plus / Premium / credit pack).
  Future<void> purchasePackage(Package pkg) async {
    busy.value = true;
    try {
      await Purchases.purchasePackage(pkg);
      await refreshSubscription();
      await refreshCredits();
      Get.snackbar('Vita', 'Purchase successful');
    } catch (e) {
      // RevenueCat errors include the user cancelling the sheet; only surface
      // real failures.
      final msg = '$e';
      if (!msg.toLowerCase().contains('cancel')) {
        Get.snackbar('Purchase failed', msg);
      }
    } finally {
      busy.value = false;
    }
  }

  Future<void> restorePurchases() async {
    busy.value = true;
    try {
      await Purchases.restorePurchases();
      await refreshSubscription();
      await refreshCredits();
      Get.snackbar('Vita', 'Purchases restored');
    } catch (e) {
      Get.snackbar('Restore failed', '$e');
    } finally {
      busy.value = false;
    }
  }
}
