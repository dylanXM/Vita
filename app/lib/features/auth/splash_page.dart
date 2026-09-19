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
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: VitaColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0x3307C160), blurRadius: 28, offset: Offset(0, 10)),
                ],
              ),
              child: Icon(Icons.favorite, color: Colors.white, size: 46),
            ),
            SizedBox(height: 20),
            Text(
              'Vita',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: VitaColors.text, letterSpacing: 0.5),
            ),
            SizedBox(height: 6),
            Text(
              'A companion who lives somewhere else',
              style: TextStyle(fontSize: 13, color: VitaColors.subText),
            ),
          ],
        ),
      ),
    );
  }
}
