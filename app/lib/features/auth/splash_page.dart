import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../core/token_storage.dart';
import '../../core/app_content_controller.dart';
import 'auth_controller.dart';

/// Startup gate: restores the stored session and routes to the shell or login.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    String? token;
    try {
      token = await TokenStorage.read();
    } catch (_) {
      // Secure storage unavailable (e.g. fresh install) — treat as signed out.
    }
    if (!mounted) return;
    await AppContentController.to.load();
    if (!mounted) return;
    // Existing signed-in installs must not be pushed through a newly added
    // first-run flow after an app upgrade.
    if ((token == null || token.isEmpty) &&
        await AppContentController.to.shouldShowOnboarding()) {
      Get.offAllNamed('/onboarding');
      return;
    }
    if (token != null && token.isNotEmpty) {
      try {
        await AuthController.to.fetchProfile();
      } catch (_) {
        await TokenStorage.clear();
        if (mounted) Get.offAllNamed('/login');
        return;
      }
      if (mounted) Get.offAllNamed('/shell');
    } else {
      Get.offAllNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/branding/vita_app_icon_1024.png',
              width: 128,
              height: 128,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 20),
            Text(
              'Vita',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: context.vita.text,
                  letterSpacing: 0.5),
            ),
            SizedBox(height: 6),
            Text(
              'auth.tagline'.tr,
              style: TextStyle(fontSize: 13, color: context.vita.subText),
            ),
          ],
        ),
      ),
    );
  }
}
