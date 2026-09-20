import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';
import 'registration_legal_consent.dart';

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
  bool _acceptedLegal = false;

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
    if (!_emailValid || !_passwordValid || !_acceptedLegal) return;
    try {
      await AuthController.to.register(
        _email.text.trim(),
        _password.text,
        _inviteCode.text,
        acceptedLegal: _acceptedLegal,
      );
      setState(() => _step = 2);
      _startCountdown();
      Get.snackbar('auth.checkInbox'.tr,
          'auth.codeSentTo'.trParams({'email': _email.text.trim()}));
    } catch (e) {
      Get.snackbar('auth.sendCodeFailed'.tr, '$e');
    }
  }

  /// Step 2: resend (re-issues the code, 60s server cooldown).
  Future<void> _resendCode() async {
    try {
      await AuthController.to.register(
        _email.text.trim(),
        _password.text,
        _inviteCode.text,
        acceptedLegal: _acceptedLegal,
      );
      _startCountdown();
      Get.snackbar('auth.checkInbox'.tr,
          'auth.codeSentTo'.trParams({'email': _email.text.trim()}));
    } catch (e) {
      Get.snackbar('auth.sendCodeFailed'.tr, '$e');
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
      Get.snackbar('auth.verificationFailed'.tr, '$e');
    }
  }

  Future<void> _googleRegister() async {
    if (!_acceptedLegal) return;
    try {
      if (await AuthController.to.loginWithGoogle(acceptedLegal: true)) {
        Get.offAllNamed('/shell');
      }
    } catch (e) {
      Get.snackbar('auth.googleFailed'.tr, '$e');
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
                  'auth.createAccount'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.signupSubtitle'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: context.vita.subText),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _email,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(hintText: 'auth.email'.tr),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  onChanged: (_) => setState(() {}),
                  obscureText: _obscurePassword,
                  autocorrect: false,
                  onSubmitted: (_) => _sendCode(),
                  decoration: InputDecoration(
                    hintText: 'auth.passwordHint'.tr,
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
                const SizedBox(height: 16),
                RegistrationLegalConsent(
                  accepted: _acceptedLegal,
                  onChanged: (value) => setState(() => _acceptedLegal = value),
                ),
                const SizedBox(height: 20),
                Obx(
                  () => ElevatedButton(
                    key: const ValueKey('register-get-code-button'),
                    onPressed: (AuthController.to.loading.value ||
                            !_emailValid ||
                            !_passwordValid ||
                            !_acceptedLegal)
                        ? null
                        : _sendCode,
                    child: AuthController.to.loading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('auth.getCode'.tr),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'auth.or'.tr,
                        style: TextStyle(
                          color: context.vita.subText.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                Obx(
                  () => OutlinedButton.icon(
                    key: const ValueKey('register-google-button'),
                    onPressed:
                        AuthController.to.loading.value || !_acceptedLegal
                            ? null
                            : _googleRegister,
                    icon: Icon(Icons.g_mobiledata,
                        color: context.vita.text, size: 26),
                    label: Text('auth.continueGoogle'.tr),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.vita.text,
                      side: BorderSide(color: context.vita.divider),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'auth.alreadyAccount'.tr,
                      style: TextStyle(
                          fontSize: 13.5, color: context.vita.subText),
                    ),
                    TextButton(
                      onPressed: () => Get.back(),
                      child: Text(
                        'auth.login'.tr,
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
                  'auth.verifyEmail'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.sixDigitSent'.trParams({'email': _email.text.trim()}),
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
                    onChanged: (_) => setState(() {}),
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
                          ? 'auth.resendIn'.trParams({'seconds': '$_countdown'})
                          : 'auth.resendCode'.tr,
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
                        : Text('auth.verifySignIn'.tr),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'auth.spamHint'.tr,
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
