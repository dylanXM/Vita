import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_list_controller.dart';
import '../memories/memories_page.dart';
import 'ai_pet_avatar.dart';
import 'ai_pet_desktop_controller.dart';
import 'ai_pet_home_page.dart';

class AIPetsPage extends StatefulWidget {
  const AIPetsPage({super.key});

  @override
  State<AIPetsPage> createState() => _AIPetsPageState();
}

class _AIPetsPageState extends State<AIPetsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _breeds = const [];

  @override
  void initState() {
    super.initState();
    AnalyticsService.to.track('ai_pets_viewed', category: 'companion');
    _load();
  }

  bool _autoJumped = false;

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/v1/ai-pets/breeds');
      final items = data is Map ? data['items'] : null;
      if (mounted && items is List) {
        final breeds = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        setState(() => _breeds = breeds);
        // If already adopted a pet, jump straight to its detail page and
        // replace this list page so the user cannot adopt another one.
        if (!_autoJumped) {
          for (final breed in breeds) {
            final adoptedId = '${breed['adopted_companion_id'] ?? ''}';
            if (adoptedId.isNotEmpty) {
              _autoJumped = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Get.off(() => AIPetHomePage(
                      companionId: adoptedId,
                      name:
                          '${breed['adopted_companion_name'] ?? breed['name'] ?? ''}',
                      avatarUrl: '${breed['avatar_url'] ?? ''}',
                      species: '${breed['species'] ?? ''}',
                    ));
              });
              break;
            }
          }
        }
      }
    } catch (_) {
      // Keep Explore usable when remote pet content is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBreed(Map<String, dynamic> breed) async {
    final adoptedId = '${breed['adopted_companion_id'] ?? ''}';
    if (adoptedId.isNotEmpty) {
      await Get.to(() => AIPetHomePage(
            companionId: adoptedId,
            name: '${breed['adopted_companion_name'] ?? breed['name'] ?? ''}',
            avatarUrl: '${breed['avatar_url'] ?? ''}',
            species: '${breed['species'] ?? ''}',
          ));
      await _load();
      return;
    }
    if (breed['can_adopt'] != true) {
      Get.snackbar(
          'subscription.required.title'.tr, 'aiPets.subscriptionRequired'.tr);
      Get.toNamed('/subscription');
      return;
    }
    final nameController =
        TextEditingController(text: '${breed['name'] ?? ''}');
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('aiPets.adoptTitle'.tr),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${breed['description'] ?? ''}'),
              const SizedBox(height: 16),
              TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: InputDecoration(labelText: 'aiPets.petName'.tr)),
            ]),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Get.back(result: false),
              child: Text('common.cancel'.tr, style: const TextStyle(color: CupertinoColors.systemGrey))),
          CupertinoDialogAction(
              onPressed: () => Get.back(result: true),
              child: Text('aiPets.adopt'.tr)),
        ],
      ),
    );
    if (confirmed != true || nameController.text.trim().isEmpty) {
      nameController.dispose();
      return;
    }
    try {
      final result = await ApiClient.instance.post('/v1/ai-pets/adopt', data: {
        'breed_id': breed['id'],
        'name': nameController.text.trim(),
      });
      final companionId =
          result is Map ? '${result['companion_id'] ?? ''}' : '';
      AnalyticsService.to.track('ai_pet_adopted',
          category: 'companion',
          properties: {
            'breed_id': '${breed['id'] ?? ''}',
            'companion_id': companionId
          });
      await Future.wait([
        ChatListController.to.load(),
        MemoriesController.to.loadCompanions(),
        if (Get.isRegistered<AIPetDesktopController>())
          AIPetDesktopController.to.refreshPet(),
      ]);
      if (mounted && companionId.isNotEmpty) {
        await Get.to(() => AIPetHomePage(
              companionId: companionId,
              name: nameController.text.trim(),
              avatarUrl: '${breed['avatar_url'] ?? ''}',
              species: '${breed['species'] ?? ''}',
            ));
      }
      await _load();
    } on ApiException catch (error) {
      if (error.action == 'open_subscription') {
        Get.snackbar(
            'subscription.required.title'.tr, 'aiPets.subscriptionRequired'.tr);
        Get.toNamed('/subscription');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      nameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text('aiPets.title'.tr)),
      body: _loading && _breeds.isEmpty
          ? ListView.builder(
              itemCount: 4,
              itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true))
          : RefreshIndicator(
              onRefresh: _load,
              child: _breeds.isEmpty
                  ? ListView(children: [
                      SizedBox(
                          height: MediaQuery.sizeOf(context).height * .6,
                          child: VitaEmpty(
                              icon: Icons.pets_outlined,
                              title: 'aiPets.empty'.tr,
                              subtitle: 'aiPets.emptySub'.tr))
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      itemCount: _breeds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _BreedCard(
                          breed: _breeds[index],
                          onTap: () => _openBreed(_breeds[index])),
                    ),
            ),
    );
  }
}

class _BreedCard extends StatelessWidget {
  const _BreedCard({required this.breed, required this.onTap});
  final Map<String, dynamic> breed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final adopted = '${breed['adopted_companion_id'] ?? ''}'.isNotEmpty;
    final allowed = breed['can_adopt'] == true;
    return VitaCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                    width: 76,
                    height: 76,
                    child: AIPetAvatar(
                        name: '${breed['name'] ?? ''}',
                        imageUrl: '${breed['avatar_url'] ?? ''}'))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${breed['name'] ?? ''}',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: context.vita.text)),
                  const SizedBox(height: 2),
                  Text(
                      '${breed['species'] ?? ''} · ${breed['personality'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: context.vita.subText)),
                  const SizedBox(height: 7),
                  Text('${breed['description'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: context.vita.text)),
                  const SizedBox(height: 8),
                  Text(
                      adopted
                          ? 'aiPets.adopted'.tr
                          : allowed
                              ? 'aiPets.available'.tr
                              : 'aiPets.planLocked'.tr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: adopted || allowed
                              ? context.vita.green
                              : context.vita.subText)),
                ])),
            Icon(Icons.chevron_right, color: context.vita.chevron),
          ]),
        ),
      ),
    );
  }
}
