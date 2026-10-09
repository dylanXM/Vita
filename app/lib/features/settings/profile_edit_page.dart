import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

/// Edit the signed-in user's display name and avatar. Reached from Settings →
/// Account → Profile. Follows the flat WeChat-style grouped list used across
/// the app: light-gray canvas, white surfaces, hairline separators, 17 px
/// centered navigation title.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _nicknameController = TextEditingController();
  bool _initialized = false;

  /// Current avatar URL. Null means "keep the existing one"; a value means the
  /// user picked a new image (either already uploaded or pending upload).
  String? _avatarUrl;

  /// True while a new avatar is being picked / uploaded.
  bool _uploadingAvatar = false;

  /// True while the save request is in flight.
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _nicknameController.text = AuthController.to.nickname;
      _avatarUrl = AuthController.to.avatarUrl;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );
    } catch (_) {
      if (!mounted) return;
      VitaNotice.error('profile.avatar'.tr, 'profile.pickFailed'.tr);
      return;
    }
    if (image == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final result = await ApiClient.instance
          .upload('/v1/media/upload', image.path, kind: 'image');
      final map = Map<String, dynamic>.from(result as Map);
      final url = map['url'] as String? ?? '';
      if (url.isEmpty) throw ApiException('upload returned no url');
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      if (!mounted) return;
      VitaNotice.error('profile.avatar'.tr,
          e is ApiException ? e.message : 'profile.uploadFailed'.tr);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _uploadingAvatar) return;
    final nickname = _nicknameController.text.trim();
    if (nickname.runes.length > 30) {
      VitaNotice.warning('profile.nickname'.tr, 'profile.nicknameTooLong'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthController.to.updateProfile(
        nickname: nickname,
        avatarUrl: _avatarUrl ?? '',
      );
      if (!mounted) return;
      Get.back();
    } catch (e) {
      if (!mounted) return;
      VitaNotice.error('profile.saveFailed'.tr,
          e is ApiException ? e.message : 'profile.saveFailed'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final existingAvatar = AuthController.to.avatarUrl;

    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text('profile.edit.title'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          VitaCard(
            radius: 12,
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: Column(children: [
              SizedBox(
                height: 80,
                child: InkWell(
                  onTap: _uploadingAvatar || _saving ? null : _pickAvatar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                        child: Text('profile.avatar'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: vita.text, fontSize: 15)),
                      ),
                      Stack(alignment: Alignment.center, children: [
                        _AvatarCircle(
                          url: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                              ? _avatarUrl!
                              : existingAvatar,
                          radius: 27,
                        ),
                        if (_uploadingAvatar)
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ]),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: vita.chevron),
                    ]),
                  ),
                ),
              ),
              const Divider(height: 0.5, indent: 16),
              SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Text('profile.nickname'.tr,
                        style: TextStyle(color: vita.text, fontSize: 15)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _nicknameController,
                        maxLength: 30,
                        textAlign: TextAlign.right,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'profile.nickname.hint'.tr,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        style: TextStyle(fontSize: 15, color: vita.text),
                      ),
                    ),
                  ]),
                ),
              ),
              const Divider(height: 0.5, indent: 16),
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Text('auth.email'.tr,
                        style: TextStyle(color: vita.text, fontSize: 15)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(AuthController.to.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: vita.subText, fontSize: 13)),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('profile.nickname.help'.tr, style: vita.sub),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _saving || _uploadingAvatar ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text('common.save'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round avatar used on the edit page. Falls back to the first letter of the
/// email when no image is set, matching [VitaAvatar]'s fallback behavior.
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.url, this.radius = 48});

  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final source = url.trim();
    if (source.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: VitaMediaImage(url: source),
        ),
      );
    }
    final email = AuthController.to.email;
    final initial = email.isEmpty ? '?' : email[0].toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: vita.greenTint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: vita.green,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
