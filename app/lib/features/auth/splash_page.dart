import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../core/token_storage.dart';

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
    if (token != null && token.isNotEmpty) {
      Get.offAllNamed('/shell');
    } else {
      Get.offAllNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: VitaColors.green,
              child: Icon(Icons.favorite, color: Colors.white, size: 34),
            ),
            SizedBox(height: 16),
            Text(
              'Vita',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: VitaColors.text),
            ),
          ],
        ),
      ),
    );
  }
}
