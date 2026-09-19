import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/bootstrap.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/splash_page.dart';
import 'features/billing/credits_page.dart';
import 'features/billing/subscription_page.dart';
import 'features/companion/companion_create_page.dart';
import 'features/shell/shell_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initControllers();
  runApp(const VitaApp());
}

class VitaApp extends StatelessWidget {
  const VitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Vita',
      theme: VitaTheme.light,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      defaultTransition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 280),
      getPages: [
        GetPage(name: '/', page: () => const SplashPage()),
        GetPage(name: '/login', page: () => const LoginPage(), transition: Transition.cupertino),
        GetPage(name: '/register', page: () => const RegisterPage(), transition: Transition.cupertino),
        GetPage(name: '/shell', page: () => const ShellPage(), transition: Transition.fadeIn),
        GetPage(name: '/companion/create', page: () => const CompanionCreatePage(), transition: Transition.cupertino),
        GetPage(name: '/subscription', page: () => const SubscriptionPage(), transition: Transition.cupertino),
        GetPage(name: '/credits', page: () => const CreditsPage(), transition: Transition.cupertino),
      ],
    );
  }
}
