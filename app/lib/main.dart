import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import 'core/bootstrap.dart';
import 'core/i18n/translations.dart';
import 'core/push_notification_service.dart';
import 'core/settings_controller.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/splash_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/billing/credits_page.dart';
import 'features/billing/subscription_page.dart';
import 'features/companion/companion_create_page.dart';
import 'features/shell/shell_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.instance.initialize();
  initControllers();
  // Wait for persisted language/theme preferences before the first frame
  // so the app boots directly into the user's settings.
  await VitaSettingsController.to.ready.future;
  runApp(const VitaApp());
}

class VitaApp extends StatefulWidget {
  const VitaApp({super.key});

  @override
  State<VitaApp> createState() => _VitaAppState();
}

class _VitaAppState extends State<VitaApp> {
  late final VitaSettingsController _settings = VitaSettingsController.to;

  @override
  void initState() {
    super.initState();
    _settings.onPreferenceChanged = () => setState(() {});
  }

  @override
  void dispose() {
    _settings.onPreferenceChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Vita',
      theme: VitaTheme.light,
      darkTheme: VitaTheme.dark,
      themeMode: _settings.appliedThemeMode,
      locale: Get.locale,
      fallbackLocale: const Locale('en'),
      supportedLocales: VitaSettingsController.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      translations: VitaTranslations(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      defaultTransition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 280),
      getPages: [
        GetPage(name: '/', page: () => const SplashPage()),
        GetPage(
          name: '/onboarding',
          page: () => const OnboardingPage(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: '/login',
          page: () => const LoginPage(),
          transition: Transition.cupertino,
        ),
        GetPage(
          name: '/register',
          page: () => const RegisterPage(),
          transition: Transition.cupertino,
        ),
        GetPage(
          name: '/shell',
          page: () => const ShellPage(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: '/companion/create',
          page: () => const CompanionCreatePage(),
          transition: Transition.cupertino,
        ),
        GetPage(
          name: '/subscription',
          page: () => const SubscriptionPage(),
          transition: Transition.cupertino,
        ),
        GetPage(
          name: '/credits',
          page: () => const CreditsPage(),
          transition: Transition.cupertino,
        ),
      ],
    );
  }
}
