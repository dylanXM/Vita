import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../life/life_detail_page.dart';

class MemoriesController extends GetxController {
  static MemoriesController get to => Get.find();

  final companionsLoading = false.obs;
  final memoriesLoading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;
  final memories = <Map<String, dynamic>>[].obs;
  final activeCompanionId = RxnString();
  final searchQuery = ''.obs;

  /// Companions filtered by name / city / occupation for the search box.
  List<Map<String, dynamic>> get filteredCompanions {
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isEmpty) return List.of(companions);
    return companions.where((companion) {
      final name = (companion['name'] as String? ?? '').toLowerCase();
      final city = (companion['city'] as String? ?? '').toLowerCase();
      final occupation =
          (companion['occupation'] as String? ?? '').toLowerCase();
      return name.contains(q) || city.contains(q) || occupation.contains(q);
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    loadCompanions();
  }

  Future<void> loadCompanions() async {
    companionsLoading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (data is List) {
        companions.assignAll(
          data
              .whereType<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {
    } finally {
      companionsLoading.value = false;
    }
  }

  Future<void> loadMemories(String companionId) async {
    activeCompanionId.value = companionId;
    memories.clear();
    memoriesLoading.value = true;
    AnalyticsService.to.track(
      'memory_list_viewed',
      category: 'life',
      properties: {'companion_id': companionId},
    );
    try {
      final data =
          await ApiClient.instance.get('/v1/companions/$companionId/memories');
      if (activeCompanionId.value != companionId) return;
      final list = data is Map ? data['memories'] : data;
      if (list is List) {
        memories.assignAll(
          list
              .whereType<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {
    } finally {
      if (activeCompanionId.value == companionId) {
        memoriesLoading.value = false;
      }
    }
  }

  Future<void> updateMemory(
    String companionId,
    String memoryId,
    String content,
  ) async {
    await ApiClient.instance.put(
      '/v1/companions/$companionId/memories/$memoryId',
      data: {'content': content},
    );
    await loadMemories(companionId);
  }

  Future<void> deleteMemory(String companionId, String memoryId) async {
    await ApiClient.instance
        .delete('/v1/companions/$companionId/memories/$memoryId');
    if (activeCompanionId.value == companionId) {
      memories.removeWhere((item) => item['id'] == memoryId);
    }
  }
}

/// First level: a contact-style list. Memories from different companions are
/// deliberately kept separate instead of sharing an in-page selector.
///
/// It is a root dock tab, so it carries the same borderless top header as the
/// other tabs and its list scrolls behind the floating glass tab bar.
class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MemoriesController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      // Bottom is open so the list scrolls behind the glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VitaTabHeader(title: 'memories.title'.tr, showDivider: false),
            const _MemorySearchBox(),
            Expanded(child: Obx(() => _buildBody(context, controller))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MemoriesController controller) {
    if (controller.companionsLoading.value && controller.companions.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: 6,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: true),
      );
    }
    if (controller.companions.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadCompanions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: VitaEmpty(
                icon: Icons.star_border,
                title: 'memories.createFirst'.tr,
                subtitle: 'memories.createFirstSub'.tr,
              ),
            ),
          ],
        ),
      );
    }

    final list = controller.filteredCompanions;
    if (list.isEmpty) {
      return VitaEmpty(
        icon: Icons.search,
        title: 'memories.noResults'.tr,
        subtitle: 'memories.noResultsSub'.tr,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadCompanions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        itemCount: list.length,
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          indent: 72,
          color: context.vita.divider,
        ),
        itemBuilder: (context, index) => _MemoryContactTile(
          companion: list[index],
        ),
      ),
    );
  }
}

/// WeChat-style rounded search field filtering the companion list.
class _MemorySearchBox extends StatelessWidget {
  const _MemorySearchBox();

  @override
  Widget build(BuildContext context) {
    final controller = MemoriesController.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: TextField(
        onChanged: (v) => controller.searchQuery.value = v,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'memories.search'.tr,
          hintStyle: TextStyle(color: context.vita.hint, fontSize: 14),
          prefixIcon: const SizedBox(
            height: 40,
            width: 38,
            child: Center(
              child: Icon(Icons.search, size: 18, color: Color(0xFFBBBBBB)),
            ),
          ),
          filled: true,
          fillColor: context.vita.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 40),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _MemoryContactTile extends StatelessWidget {
  const _MemoryContactTile({required this.companion});

  final Map<String, dynamic> companion;

  @override
  Widget build(BuildContext context) {
    final id = companion['id'] as String? ?? '';
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    final city = (companion['city'] as String? ?? '').trim();
    final occupation = (companion['occupation'] as String? ?? '').trim();
    final profile =
        [city, occupation].where((item) => item.isNotEmpty).join(' · ');

    return Material(
      color: context.vita.surface,
      child: InkWell(
        onTap: id.isEmpty
            ? null
            : () {
                AnalyticsService.to.track(
                  'memory_companion_opened',
                  category: 'navigation',
                  properties: {'companion_id': id},
                );
                Get.to(
                  () => MemoryDetailPage(companion: companion),
                  transition: Transition.cupertino,
                  duration: const Duration(milliseconds: 300),
                );
              },
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                VitaAvatar(
                  name: name,
                  radius: 22,
                  imageUrl: companion['portrait_url'] as String?,
                  borderRadius: BorderRadius.circular(8),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: context.vita.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.isEmpty ? 'memories.subtitle'.tr : profile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.vita.subText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.vita.chevron),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Second level: all memories belonging to one companion.
class MemoryDetailPage extends StatefulWidget {
  const MemoryDetailPage({super.key, required this.companion});

  final Map<String, dynamic> companion;

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  MemoriesController get controller => MemoriesController.to;
  String get companionId => widget.companion['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    controller.loadMemories(companionId);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.companion['name'] as String? ?? 'memories.title'.tr;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        leading: const VitaBackButton(),
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            color: context.vita.subText,
            onPressed: () => Get.to(
              () => LifeDetailPage(companion: widget.companion),
              transition: Transition.cupertino,
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Obx(() => _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (controller.memoriesLoading.value && controller.memories.isEmpty) {
      return ListView.builder(
        itemCount: 5,
        itemBuilder: (_, __) => const VitaSkeletonCard(withAvatar: false),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.loadMemories(companionId),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
              child: _CompanionMemoryHeader(companion: widget.companion)),
          if (controller.memories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: VitaEmpty(
                icon: Icons.star_border,
                title: 'memories.empty'.tr,
                subtitle: 'memories.emptySub'.tr,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_buildGroupedTiles(context)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedTiles(BuildContext context) {
    final tiles = <Widget>[];
    DateTime? prevDay;
    for (var i = 0; i < controller.memories.length; i++) {
      final m = controller.memories[i];
      final t = DateTime.tryParse(m['event_time'] as String? ??
              m['created_at'] as String? ??
              '') ??
          DateTime.now();
      final day = DateTime(t.year, t.month, t.day);
      if (prevDay == null || day != prevDay) {
        tiles.add(_DateSectionHeader(label: formatDateSeparator(t.toLocal())));
      }
      tiles.add(_MemoryTile(
        companionId: companionId,
        memory: m,
      ));
      prevDay = day;
    }
    return tiles;
  }
}

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.vita.subText,
        ),
      ),
    );
  }
}

class _CompanionMemoryHeader extends StatelessWidget {
  const _CompanionMemoryHeader({required this.companion});

  final Map<String, dynamic> companion;

  @override
  Widget build(BuildContext context) {
    final name = companion['name'] as String? ?? 'chat.companion'.tr;
    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          VitaAvatar(
            name: name,
            radius: 30,
            imageUrl: companion['portrait_url'] as String?,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.vita.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'memories.subtitle'.tr,
                  style: TextStyle(fontSize: 13, color: context.vita.subText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.companionId, required this.memory});

  final String companionId;
  final Map<String, dynamic> memory;

  @override
  Widget build(BuildContext context) {
    final content = memory['content'] as String? ?? '';
    final title = (memory['title'] as String? ?? '').trim();
    final type = (memory['type'] as String? ?? 'memory').trim();
    final readonly = memory['readonly'] == true;

    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.vita.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              readonly ? Icons.bookmark_outline : Icons.star_outline,
              size: 18,
              color: context.vita.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: context.vita.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  content.tr,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.vita.text,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  type,
                  style: TextStyle(fontSize: 12, color: context.vita.subText),
                ),
              ],
            ),
          ),
          if (!readonly)
            Builder(builder: (btnCtx) {
              return GestureDetector(
                onTapDown: (details) {
                  final box = btnCtx.findRenderObject() as RenderBox;
                  final center = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
                  _showWeChatMenu(context, center);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(Icons.more_horiz, color: Color(0xFF999999), size: 20),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showWeChatMenu(BuildContext context, Offset tapPos) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayCtx) => Stack(children: [
        GestureDetector(
          onTap: () => entry.remove(),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          right: MediaQuery.of(context).size.width - tapPos.dx - 12,
          top: tapPos.dy + 12,
          child: Material(
            color: Colors.transparent,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topRight, children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4C4C4C),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _MenuItem(
                      icon: Icons.delete,
                      label: 'memories.delete'.tr,
                      onTap: () { entry.remove(); _deleteMemory(context); },
                    ),
                  ]),
              ),
              Positioned(
                top: -7,
                right: 6,
                child: CustomPaint(
                  size: const Size(12, 7),
                  painter: _MenuArrowPainter(),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
    Overlay.of(context).insert(entry);
  }

  Future<void> _deleteMemory(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text('memories.delete'.tr),
        content: Text('memories.deleteConfirm'.tr),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr, style: const TextStyle(color: CupertinoColors.systemGrey)),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('memories.delete'.tr),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await MemoriesController.to.deleteMemory(
        companionId,
        memory['id'] as String,
      );
    }
  }
}


class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ]),
      ),
    );
  }
}

class _MenuArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF4C4C4C);
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
