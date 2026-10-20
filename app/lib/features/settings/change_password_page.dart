import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool _reset = false;
  bool _busy = false;
  bool _sending = false;
  DateTime? _resendAt;

  Future<void> _sendCode() async {
    if (_sending || _busy) return;
    if (_resendAt != null && DateTime.now().isBefore(_resendAt!)) {
      VitaNotice.info('password.title'.tr, 'password.wait'.tr);
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiClient.instance.post('/v1/me/password/code');
      _resendAt = DateTime.now().add(const Duration(seconds: 60));
      if (mounted) VitaNotice.success('password.title'.tr, 'password.sent'.tr);
    } catch (_) {
      if (mounted)
        VitaNotice.error('password.title'.tr, 'password.sendFailed'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _sending || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ApiClient.instance.put('/v1/me/password', data: {
        'new_password': _next.text,
        if (_reset)
          'code': _code.text.trim()
        else
          'current_password': _current.text,
      });
      if (!mounted) return;
      Get.back();
      VitaNotice.success('password.title'.tr, 'password.saved'.tr);
    } catch (_) {
      if (mounted) VitaNotice.error('password.title'.tr, 'password.failed'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.vita.pageBg,
        appBar: AppBar(
            leading: const VitaBackButton(), title: Text('password.title'.tr)),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              if (_reset) ...[
                Text('password.resetInfo'.tr, style: context.vita.sub),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _code,
                    enabled: !_busy && !_sending,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'password.code'.tr),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                            ? null
                            : 'password.codeError'.tr),
                TextButton(
                    onPressed: _busy || _sending ? null : _sendCode,
                    child: Text('password.send'.tr)),
              ] else
                TextFormField(
                    controller: _current,
                    enabled: !_busy,
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: 'password.current'.tr),
                    validator: (value) => value == null || value.isEmpty
                        ? 'password.required'.tr
                        : null),
              const SizedBox(height: 16),
              TextFormField(
                  controller: _next,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'password.new'.tr),
                  validator: (value) => (value ?? '').runes.length < 6 ||
                          utf8.encode(value ?? '').length > 72
                      ? 'password.length'.tr
                      : null),
              const SizedBox(height: 16),
              TextFormField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'password.confirm'.tr),
                  validator: (value) =>
                      value != _next.text ? 'password.mismatch'.tr : null),
              const SizedBox(height: 24),
              ElevatedButton(
                  onPressed: _busy || _sending ? null : _save,
                  child: Text('common.save'.tr)),
              TextButton(
                  onPressed: _busy || _sending
                      ? null
                      : () => setState(() {
                            _reset = !_reset;
                            _form.currentState?.reset();
                          }),
                  child: Text(_reset
                      ? 'password.useCurrent'.tr
                      : 'password.forgot'.tr)),
            ])),
      );
}
