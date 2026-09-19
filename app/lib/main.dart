import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/bootstrap.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
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
      getPages: [
        GetPage(name: '/', page: () => const SplashPage()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/shell', page: () => const ShellPage()),
        GetPage(name: '/companion/create', page: () => const CompanionCreatePage()),
        GetPage(name: '/subscription', page: () => const SubscriptionPage()),
        GetPage(name: '/credits', page: () => const CreditsPage()),
      ],
    );
  }
}
