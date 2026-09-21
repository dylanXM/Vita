import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_list_controller.dart';
import '../chat/chat_page.dart';
import '../life/life_detail_page.dart';
import '../life/life_page.dart';
import '../memories/memories_page.dart';

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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/v1/ai-pets/breeds');
      final items = data is Map ? data['items'] : null;
      if (mounted && items is List) {
        setState(() => _breeds = items
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList());
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
    final confirmed = await Get.dialog<bool>(AlertDialog(
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
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr)),
        FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('aiPets.adopt'.tr)),
      ],
    ));
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
        LifeController.to.loadCompanions(),
        MemoriesController.to.loadCompanions(),
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
      appBar: AppBar(title: Text('aiPets.title'.tr)),
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
            VitaAvatar(
                name: '${breed['name'] ?? ''}',
                radius: 38,
                imageUrl: '${breed['avatar_url'] ?? ''}',
                borderRadius: BorderRadius.circular(16)),
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

class AIPetHomePage extends StatefulWidget {
  const AIPetHomePage(
      {super.key,
      required this.companionId,
      required this.name,
      required this.avatarUrl,
      required this.species});
  final String companionId;
  final String name;
  final String avatarUrl;
  final String species;

  @override
  State<AIPetHomePage> createState() => _AIPetHomePageState();
}

class _AIPetHomePageState extends State<AIPetHomePage> {
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _feeding = false;

  Map<String, dynamic> get _companion => {
        'id': widget.companionId,
        'name': widget.name,
        'portrait_url': widget.avatarUrl,
        'occupation': widget.species,
        'creation_source': 'ai_pet',
        'friendship_active': true,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/ai-pets/${widget.companionId}/state');
      if (mounted && data is Map) {
        setState(() => _state = Map<String, dynamic>.from(data));
      }
    } on ApiException catch (error) {
      if (mounted) Get.snackbar('aiPets.error'.tr, error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _feed() async {
    if (_feeding) return;
    setState(() => _feeding = true);
    try {
      final data = await ApiClient.instance
          .post('/v1/ai-pets/${widget.companionId}/feed', data: {
        'idempotency_key':
            'pet-feed-${widget.companionId}-${DateTime.now().microsecondsSinceEpoch}'
      });
      final state = data is Map ? data['state'] : null;
      if (mounted && state is Map) {
        setState(() => _state = Map<String, dynamic>.from(state));
      }
      Get.snackbar('aiPets.fed'.tr, 'aiPets.fedSub'.tr);
    } on ApiException catch (error) {
      if (error.code == 'insufficient_credits') {
        Get.snackbar('aiPets.notEnoughCoins'.tr, 'aiPets.notEnoughCoinsSub'.tr);
        Get.toNamed('/credits');
      } else {
        Get.snackbar('aiPets.error'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _feeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state ?? const <String, dynamic>{};
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    VitaCard(
                        child: Column(children: [
                      VitaAvatar(
                          name: widget.name,
                          radius: 58,
                          imageUrl: widget.avatarUrl,
                          borderRadius: BorderRadius.circular(24)),
                      const SizedBox(height: 12),
                      Text(widget.name,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: context.vita.text)),
                      Text(
                          '${widget.species} · ${'aiPets.level'.trParams({
                                'level': '${state['level'] ?? 1}'
                              })}',
                          style: TextStyle(color: context.vita.subText)),
                      const SizedBox(height: 16),
                      _StatusBar(
                          label: 'aiPets.hunger'.tr,
                          value: (state['hunger'] as num?)?.toInt() ?? 0,
                          color: Colors.orange),
                      _StatusBar(
                          label: 'aiPets.happiness'.tr,
                          value: (state['happiness'] as num?)?.toInt() ?? 0,
                          color: Colors.pink),
                      _StatusBar(
                          label: 'aiPets.energy'.tr,
                          value: (state['energy'] as num?)?.toInt() ?? 0,
                          color: Colors.blue),
                      _StatusBar(
                          label: 'aiPets.health'.tr,
                          value: (state['health'] as num?)?.toInt() ?? 0,
                          color: context.vita.green),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                'aiPets.experience'.trParams(
                                    {'value': '${state['experience'] ?? 0}'}),
                                style: TextStyle(color: context.vita.subText)),
                            Text(
                                'aiPets.coins'.trParams(
                                    {'value': '${state['coins'] ?? 0}'}),
                                style: TextStyle(color: context.vita.subText))
                          ]),
                      const SizedBox(height: 14),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              onPressed: _feeding ? null : _feed,
                              icon: const Icon(Icons.restaurant),
                              label: Text(_feeding
                                  ? 'aiPets.feeding'.tr
                                  : 'aiPets.feed'.trParams({
                                      'coins': '${state['feed_coin_cost'] ?? 5}'
                                    })))),
                    ])),
                    const SizedBox(height: 12),
                    VitaCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(children: [
                          VitaListTile(
                              icon: Icons.chat_bubble_outline,
                              title: 'aiPets.chat'.tr,
                              onTap: () => Get.to(() => ChatPage(
                                  companionId: widget.companionId,
                                  name: widget.name,
                                  companion: _companion))),
                          VitaListTile(
                              icon: Icons.auto_stories_outlined,
                              title: 'aiPets.life'.tr,
                              onTap: () => Get.to(
                                  () => LifeDetailPage(companion: _companion))),
                          VitaListTile(
                              icon: Icons.star_border,
                              title: 'aiPets.memories'.tr,
                              onTap: () => Get.to(() =>
                                  MemoryDetailPage(companion: _companion))),
                        ])),
                  ]),
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(
              width: 70,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: context.vita.subText))),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                      value: value.clamp(0, 100) / 100,
                      minHeight: 9,
                      backgroundColor: context.vita.pageBg,
                      valueColor: AlwaysStoppedAnimation(color)))),
          const SizedBox(width: 10),
          SizedBox(
              width: 28,
              child: Text('$value',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: context.vita.subText))),
        ]),
      );
}
