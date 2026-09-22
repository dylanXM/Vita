import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

class DeletedCompanionsPage extends StatefulWidget {
  const DeletedCompanionsPage({super.key});

  @override
  State<DeletedCompanionsPage> createState() => _DeletedCompanionsPageState();
}

class _DeletedCompanionsPageState extends State<DeletedCompanionsPage> {
  bool _loading = true;
  String? _restoring;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/v1/companions-deleted');
      if (!mounted || data is! Map) return;
      setState(() {
        _items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } on ApiException catch (error) {
      if (mounted) {
        Get.snackbar('settings.deletedCompanions'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> companion) async {
    final id = companion['id'] as String? ?? '';
    if (id.isEmpty || _restoring != null) return;
    setState(() => _restoring = id);
    try {
      await ApiClient.instance.post('/v1/companions/$id/restore');
      if (!mounted) return;
      Get.snackbar(
        'settings.deletedCompanions'.tr,
        'deletedCompanions.restored'.tr,
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        Get.snackbar('settings.deletedCompanions'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _restoring = null);
    }
  }

  int _daysLeft(String? raw) {
    final deadline = DateTime.tryParse(raw ?? '')?.toLocal();
    if (deadline == null) return 0;
    final hours = deadline.difference(DateTime.now()).inHours;
    if (hours <= 0) return 0;
    return (hours / 24).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text('settings.deletedCompanions'.tr)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _items.isEmpty
            ? ListView.builder(
                itemCount: 5,
                itemBuilder: (_, __) => const VitaSkeletonCard(),
              )
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: VitaEmpty(
                          icon: Icons.restore_from_trash_outlined,
                          title: 'deletedCompanions.empty'.tr,
                          subtitle: 'deletedCompanions.emptySub'.tr,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      indent: 76,
                      color: context.vita.divider,
                    ),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final id = item['id'] as String? ?? '';
                      final name = item['name'] as String? ?? '';
                      final running = item['life_engine_running'] == true;
                      final days = _daysLeft(item['purge_after'] as String?);
                      return Container(
                        color: context.vita.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            VitaAvatar(
                              name: name,
                              radius: 24,
                              imageUrl: item['portrait_url'] as String?,
                              borderRadius: BorderRadius.circular(10),
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
                                      fontWeight: FontWeight.w600,
                                      color: context.vita.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${'deletedCompanions.daysLeft'.trParams({
                                          'days': '$days'
                                        })} · ${running ? 'deletedCompanions.lifeRunning'.tr : 'deletedCompanions.lifePaused'.tr}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.vita.subText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _restoring == null
                                  ? () => _restore(item)
                                  : null,
                              child: _restoring == id
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text('deletedCompanions.restore'.tr),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
