import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import '../billing/billing_controller.dart';

/// Ad units and switches are served by Admin. The client never grants credits;
/// only Google's verified server-side callback can do that.
class AdmobController extends GetxController {
  static AdmobController get to => Get.find();

  final config = Rxn<Map<String, dynamic>>();
  final loadingReward = false.obs;
  final privacyOptionsRequired = false.obs;
  Future<bool>? _sdkReady;
  bool _showingFullscreen = false;
  bool _loadingInterstitial = false;
  DateTime? _lastInterstitial;

  bool get supported => Platform.isAndroid || Platform.isIOS;
  bool get canShowRewarded =>
      supported &&
      config.value?['rewarded_enabled'] == true &&
      '${config.value?['rewarded_unit_id'] ?? ''}'.isNotEmpty;
  bool get canShowBanner =>
      supported &&
      config.value?['banner_enabled'] == true &&
      (config.value?['show_to_subscribers'] == true ||
          !BillingController.to.isSubscribed) &&
      '${config.value?['banner_unit_id'] ?? ''}'.isNotEmpty;
  bool get canShowInterstitial =>
      supported &&
      config.value?['interstitial_enabled'] == true &&
      (config.value?['show_to_subscribers'] == true ||
          !BillingController.to.isSubscribed) &&
      '${config.value?['interstitial_unit_id'] ?? ''}'.isNotEmpty;

  Future<void> refreshConfig() async {
    if (!supported) return;
    try {
      final data = await ApiClient.instance.get('/v1/ads/config');
      if (data is! Map) return;
      config.value = Map<String, dynamic>.from(data);
      if (canShowRewarded || canShowBanner || canShowInterstitial) {
        await _ensureSdk();
      }
    } catch (_) {
      config.value = null;
    }
  }

  Future<bool> _ensureSdk() async {
    final ready = await (_sdkReady ??= _prepareSdk());
    if (!ready) _sdkReady = null;
    return ready;
  }

  Future<bool> _prepareSdk() async {
    try {
      final consent = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => consent.complete(),
        (_) => consent.complete(),
      );
      await consent.future;
      final form = Completer<void>();
      await ConsentForm.loadAndShowConsentFormIfRequired(
          (_) => form.complete());
      await form.future;
      privacyOptionsRequired.value = await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!await ConsentInformation.instance.canRequestAds()) return false;
      await MobileAds.instance.initialize();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!privacyOptionsRequired.value) return;
    await ConsentForm.showPrivacyOptionsForm((_) {});
    _sdkReady = null;
  }

  Future<void> showRewarded() async {
    if (!canShowRewarded ||
        loadingReward.value ||
        _showingFullscreen ||
        !await _ensureSdk()) {
      return;
    }
    loadingReward.value = true;
    try {
      final session = await ApiClient.instance.post('/v1/ads/reward-sessions');
      final sessionId = '${session['session_id'] ?? ''}';
      final unitId = '${session['ad_unit_id'] ?? ''}';
      final userId =
          AuthController.to.profile.value?['user_id'] as String? ?? '';
      if (sessionId.isEmpty || unitId.isEmpty || userId.isEmpty) return;
      final loaded = Completer<RewardedAd?>();
      await RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => loaded.complete(ad),
          onAdFailedToLoad: (_) => loaded.complete(null),
        ),
      );
      final ad = await loaded.future;
      if (ad == null) {
        Get.snackbar('ads.title'.tr, 'ads.unavailable'.tr);
        return;
      }
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId, customData: sessionId),
      );
      _showingFullscreen = true;
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (ad) {
          _showingFullscreen = false;
          ad.dispose();
          refreshConfig();
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          _showingFullscreen = false;
          ad.dispose();
        },
      );
      await ad.show(onUserEarnedReward: (_, __) {
        Get.snackbar('ads.title'.tr, 'ads.rewardPending'.tr);
        for (final delay in [2, 5, 10, 20]) {
          Future.delayed(Duration(seconds: delay), () {
            BillingController.to.refreshCredits();
            if (delay == 20) refreshConfig();
          });
        }
      });
    } catch (_) {
      Get.snackbar('ads.title'.tr, 'ads.unavailable'.tr);
    } finally {
      loadingReward.value = false;
    }
  }

  /// Called only after a confirmed purchase or a new debit appears in the
  /// server ledger. An ad is never placed before the transaction completes.
  Future<void> maybeShowInterstitial() async {
    if (!canShowInterstitial ||
        _showingFullscreen ||
        _loadingInterstitial ||
        !await _ensureSdk()) {
      return;
    }
    final last = _lastInterstitial;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 3)) {
      return;
    }
    _loadingInterstitial = true;
    final unit = '${config.value?['interstitial_unit_id'] ?? ''}';
    final loaded = Completer<InterstitialAd?>();
    try {
      await InterstitialAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => loaded.complete(ad),
          onAdFailedToLoad: (_) => loaded.complete(null),
        ),
      );
      final ad = await loaded.future;
      if (ad == null || _showingFullscreen || !canShowInterstitial) {
        ad?.dispose();
        return;
      }
      _showingFullscreen = true;
      _lastInterstitial = DateTime.now();
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdDismissedFullScreenContent: (ad) {
          _showingFullscreen = false;
          ad.dispose();
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          _showingFullscreen = false;
          ad.dispose();
        },
      );
      await ad.show();
    } catch (_) {
      // Ads never block a paid action.
    } finally {
      _loadingInterstitial = false;
    }
  }
}

class AdmobBanner extends StatefulWidget {
  const AdmobBanner({super.key});

  @override
  State<AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<AdmobBanner> {
  BannerAd? _ad;
  Worker? _configWorker;
  bool _loaded = false;
  String _unit = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _configWorker = ever(AdmobController.to.config, (_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final ctrl = AdmobController.to;
    final unit = ctrl.canShowBanner
        ? '${ctrl.config.value?['banner_unit_id'] ?? ''}'
        : '';
    if (unit == _unit) return;
    _ad?.dispose();
    setState(() {
      _ad = null;
      _loaded = false;
      _unit = unit;
    });
    if (unit.isEmpty) return;
    if (!await ctrl._ensureSdk() ||
        !mounted ||
        _unit != unit ||
        !ctrl.canShowBanner) {
      if (_unit == unit) _unit = '';
      return;
    }
    final ad = BannerAd(
      adUnitId: unit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted && identical(_ad, ad)) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted && identical(_ad, ad)) {
            setState(() {
              _ad = null;
              _loaded = false;
              _unit = '';
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _configWorker?.dispose();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Center(
        child: SizedBox(width: 320, height: 50, child: AdWidget(ad: _ad!)));
  }
}
