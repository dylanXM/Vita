import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

class InvitationPage extends StatefulWidget {
  const InvitationPage({super.key});

  @override
  State<InvitationPage> createState() => _InvitationPageState();
}

class _InvitationPageState extends State<InvitationPage> {
  final _code = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _binding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = Map<String, dynamic>.from(
          await ApiClient.instance.get('/v1/me') as Map);
      if (!mounted) return;
      AuthController.to.profile.value = profile;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'common.loadFailed'.tr;
        });
    }
  }

  Future<void> _bind() async {
    final code = _code.text.trim().toUpperCase();
    if (_binding || code.isEmpty) return;
    setState(() => _binding = true);
    try {
      final result = await ApiClient.instance
          .post('/v1/me/invitation', data: {'invite_code': code});
      if (!mounted) return;
      final profile = {
        ...?_profile,
        'bound_invite_code': result['bound_invite_code']
      };
      AuthController.to.profile.value = profile;
      setState(() => _profile = profile);
      VitaNotice.success('invitation.title'.tr, 'invitation.boundSuccess'.tr);
    } catch (_) {
      if (mounted)
        VitaNotice.error('invitation.title'.tr, 'invitation.bindFailed'.tr);
    } finally {
      if (mounted) setState(() => _binding = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final own = _profile?['invite_code'] as String? ?? '';
    final bound = _profile?['bound_invite_code'] as String? ?? '';
    final percent = _profile?['invitation_reward_percent'];
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          leading: const VitaBackButton(), title: Text('invitation.title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: Text('common.retry'.tr)),
                ]))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  _codeCard('me.inviteCode'.tr, own, copy: true),
                  const SizedBox(height: 16),
                  _codeCard('invitation.boundCode'.tr,
                      bound.isEmpty ? 'invitation.notBound'.tr : bound),
                  if (bound.isEmpty) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        enabled: !_binding,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            labelText: 'invitation.enterCode'.tr)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _binding || _code.text.trim().isEmpty
                            ? null
                            : _bind,
                        child: Text('invitation.bind'.tr)),
                  ],
                  const SizedBox(height: 20),
                  Text('invitation.once'.tr, style: context.vita.sub),
                  const SizedBox(height: 12),
                  Text(
                      'invitation.rewardInfo'.trParams({
                        'percent': percent is num ? percent.toString() : '—'
                      }),
                      style: context.vita.sub),
                ]),
    );
  }

  Widget _codeCard(String label, String value, {bool copy = false}) => VitaCard(
        margin: EdgeInsets.zero,
        child: SizedBox(
            height: 64,
            child: Row(children: [
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vita.sub),
                    const SizedBox(height: 6),
                    SelectableText(value.isEmpty ? '—' : value,
                        maxLines: 1, style: context.vita.sectionTitle),
                  ])),
              if (copy && value.isNotEmpty)
                IconButton(
                    tooltip: 'invitation.copy'.tr,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (mounted)
                        VitaNotice.success(
                            'me.inviteCode'.tr, 'me.inviteCopied'.tr);
                    }),
            ])),
      );
}
