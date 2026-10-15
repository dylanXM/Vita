import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import 'encounter_profile.dart';

class EncounterConversations extends StatefulWidget {
  const EncounterConversations({super.key, required this.onOpen});
  final Future<void> Function(Map<String, dynamic>) onOpen;

  @override
  State<EncounterConversations> createState() => _EncounterConversationsState();
}

class _EncounterConversationsState extends State<EncounterConversations>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Timer? _timer;
  bool _loading = true, _failed = false, _refreshing = false, _foreground = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_foreground && !_refreshing && ModalRoute.of(context)?.isCurrent == true) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && ModalRoute.of(context)?.isCurrent == true) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    if (!_foreground || (_refreshing && !force)) return;
    final generation = ++_generation;
    _refreshing = true;
    try {
      final data = await ApiClient.instance.get('/v1/encounters/conversations');
      if (!mounted || generation != _generation) return;
      final items = (data['items'] as List).whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();
      setState(() { _items = items; _loading = false; _failed = false; });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _loading = false; _failed = true; });
      }
    } finally {
      if (generation == _generation) _refreshing = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final items = _items.where((item) => '${item['name'] ?? ''}'.toLowerCase().contains(query)).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        child: TextField(controller: _search, onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: 'contacts.search'.tr,
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white54),
            suffixIcon: query.isEmpty ? null : IconButton(
              tooltip: 'common.cancel'.tr,
              onPressed: () => setState(() => _search.clear()),
              icon: const Icon(Icons.close_rounded, size: 18)),
            filled: true, fillColor: const Color(0xFF2A202A),
            isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          )),
      ),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: () => _load(force: true),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 110),
            itemCount: items.isEmpty ? 1 : items.length,
            itemBuilder: (context, index) {
              if (items.isEmpty) return Padding(padding: const EdgeInsets.all(28),
                child: _failed ? TextButton(onPressed: () => _load(force: true), child: Text('encounter.error'.tr))
                  : Text('contacts.noResults'.tr, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)));
              final item = items[index];
              final unread = item['unread_count'] is num ? (item['unread_count'] as num).toInt() : 0;
              final preview = '${item['last_message'] ?? ''}';
              return SizedBox(key: ValueKey(item['id']), height: 80, child: ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(14),
                  child: EncounterAvatar(url: '${item['avatar_url'] ?? ''}', size: 52)),
                title: Text('${item['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                subtitle: preview.isEmpty ? null : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: unread > 0 ? Colors.white70 : Colors.white38, fontSize: 12)),
                trailing: unread <= 0 ? null : Container(
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFEBA2B8), borderRadius: BorderRadius.circular(12)),
                  child: Text(unread > 99 ? '99+' : '$unread', textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Color(0xFF351B30), fontSize: 11, fontWeight: FontWeight.w700))),
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  await widget.onOpen(item);
                  if (mounted) await _load(force: true);
                },
              ));
            },
          ),
        )),
    ]);
  }
}
