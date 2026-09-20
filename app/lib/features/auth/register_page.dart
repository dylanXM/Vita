import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

/// Two-step registration, mirroring the login page layout:
/// step 1 collects the email + password, step 2 the 6-digit code that the
/// backend emails. A verified code creates the account and signs the user in.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _inviteCode = TextEditingController();
  final _code = TextEditingController();
  Timer? _timer;
  int _countdown = 0;
  int _step = 1;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _inviteCode.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailValid => _email.text.contains('@') && _email.text.length > 4;

  bool get _passwordValid => _password.text.length >= 6;

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  /// Step 1: submit email + password, the backend emails the code.
  Future<void> _sendCode() async {
    if (!_emailValid || !_passwordValid) return;
    try {
      await AuthController.to.register(
        _email.text.trim(),
        _password.text,
        _inviteCode.text,
      );
      setState(() => _step = 2);
      _startCountdown();
      Get.snackbar('Check your inbox',
          'We sent a verification code to ${_email.text.trim()}');
    } catch (e) {
      Get.snackbar('Failed to send code', '$e');
    }
  }

  /// Step 2: resend (re-issues the code, 60s server cooldown).
  Future<void> _resendCode() async {
    try {
      await AuthController.to.register(
        _email.text.trim(),
        _password.text,
        _inviteCode.text,
      );
      _startCountdown();
      Get.snackbar('Check your inbox',
          'We sent a verification code to ${_email.text.trim()}');
    } catch (e) {
      Get.snackbar('Failed to send code', '$e');
    }
  }

  /// Step 2: verify the code, the account is created and the user signed in.
  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    try {
      await AuthController.to
          .verifyRegistration(_email.text.trim(), _code.text.trim());
      Get.offAllNamed('/shell');
    } catch (e) {
      Get.snackbar('Verification failed', '$e');
    }
  }

  void _back() {
    if (_step == 2) {
      _code.clear();
      setState(() => _step = 1);
    } else {
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new,
                        size: 20, color: context.vita.text),
                    onPressed: _back,
                  ),
                ],
              ),
              if (_step == 1) ...[
                const SizedBox(height: 20),
                Text(
                  'Create account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign up with your email and a password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: context.vita.subText),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Email'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  onSubmitted: (_) => _sendCode(),
                  decoration: InputDecoration(
                    hintText: 'Password (at least 6 characters)',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: context.vita.subText,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _inviteCode,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _sendCode(),
                  decoration: InputDecoration(
                    hintText: 'auth.inviteCodeOptional'.tr,
                  ),
                ),
                const SizedBox(height: 28),
                Obx(
                  () => ElevatedButton(
                    onPressed: (AuthController.to.loading.value ||
                            !_emailValid ||
                            !_passwordValid)
                        ? null
                        : _sendCode,
                    child: AuthController.to.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Get verification code'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                          fontSize: 13.5, color: context.vita.subText),
                    ),
                    TextButton(
                      onPressed: () => Get.back(),
                      child: Text(
                        'Login',
                        style: TextStyle(
                            color: context.vita.green,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 20),
                Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a 6-digit code to ${_email.text.trim()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: context.vita.subText),
                ),
                const SizedBox(height: 36),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: context.vita.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.vita.divider),
                  ),
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _verify(),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 10,
                      color: context.vita.text,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed:
                        (_countdown > 0 || AuthController.to.loading.value)
                            ? null
                            : _resendCode,
                    child: Text(
                      _countdown > 0
                          ? 'Resend in $_countdown s'
                          : 'Resend code',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _countdown > 0
                            ? context.vita.hint
                            : context.vita.green,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Obx(
                  () => ElevatedButton(
                    onPressed: (AuthController.to.loading.value ||
                            _code.text.length != 6)
                        ? null
                        : _verify,
                    child: AuthController.to.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify and sign in'),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Didn't get the code? Check your spam folder.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: context.vita.hint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
