import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../chat/chat_page.dart';

class LifeDetailPage extends StatefulWidget {
  final Map<String, dynamic> companion;
  const LifeDetailPage({super.key, required this.companion});

  @override
  State<LifeDetailPage> createState() => _LifeDetailPageState();
}

class _LifeDetailPageState extends State<LifeDetailPage> {
  int _tabIndex = 0;
  final ScrollController _scrollController = ScrollController();
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 180;
    if (show != _showTitle) setState(() => _showTitle = show);
  }

  Future<void> _confirmDelete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除联系人'),
        content: const Text('确定要删除这个联系人吗？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.companion;
    final name = c['name'] as String? ?? 'Companion';
    final city = (c['city'] as String? ?? '').trim();
    final occupation = (c['occupation'] as String? ?? '').trim();
    final portraitUrl = c['portrait_url'] as String?;
    final persona = c['persona'] as String? ?? '';

    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // AppBar - 固定，始终显示返回按钮
          SliverAppBar(
            pinned: true,
            backgroundColor: context.vita.surface,
            toolbarHeight: 44,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 22),
              onPressed: () => Get.back(),
            ),
            title: AnimatedOpacity(
              opacity: _showTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(name, style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

          // 用户信息头部
          SliverToBoxAdapter(
            child: Container(
              color: context.vita.surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // 大圆形头像居中
                  VitaAvatar(
                    name: name,
                    radius: 48,
                    imageUrl: portraitUrl,
                  ),
                  const SizedBox(height: 12),
                  // 名字
                  Text(
                    name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                  // @用户名（城市·职业）
                  Text(
                    [if (city.isNotEmpty) city, if (occupation.isNotEmpty) occupation].join(' · '),
                    style: TextStyle(fontSize: 14, color: context.vita.subText),
                  ),
                  const SizedBox(height: 12),
                  // 个人简介
                  if (persona.isNotEmpty)
                    Text(
                      persona,
                      style: TextStyle(fontSize: 14, color: context.vita.text, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 16),
                  // 两个按钮：删除 + 发起聊天
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _confirmDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('删除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Get.to(
                            () => ChatPage(companionId: c['id'] as String, name: name, companion: c),
                            transition: Transition.cupertino,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.vita.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                          ),
                          child: const Text('发起聊天', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Tab 栏固定
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabDelegate(
              child: Container(
                color: context.vita.surface,
                height: 48,
                child: Row(
                  children: [
                    _buildTab(0, '动态'),
                    _buildTab(1, 'Life'),
                    _buildTab(2, '共同回忆'),
                    _buildTab(3, '送他礼物'),
                  ],
                ),
              ),
            ),
          ),

          // Tab 内容
          SliverFillRemaining(
            hasScrollBody: true,
            child: _buildTabContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? context.vita.green : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.black : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    final c = widget.companion;
    switch (_tabIndex) {
      case 1:
        final persona = c['persona'] as String? ?? '';
        final habits = c['life_habits'] as String? ?? '';
        final goal = c['life_goal'] as String? ?? '';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (persona.isNotEmpty) ...[
              Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.vita.text)),
              const SizedBox(height: 8),
              Text(persona, style: TextStyle(fontSize: 15, color: context.vita.text, height: 1.5)),
              const SizedBox(height: 20),
            ],
            if (habits.isNotEmpty) ...[
              Text('Daily Habits', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.vita.text)),
              const SizedBox(height: 8),
              Text(habits, style: TextStyle(fontSize: 15, color: context.vita.text, height: 1.5)),
              const SizedBox(height: 20),
            ],
            if (goal.isNotEmpty) ...[
              Text('Life Goals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.vita.text)),
              const SizedBox(height: 8),
              Text(goal, style: TextStyle(fontSize: 15, color: context.vita.text, height: 1.5)),
            ],
          ],
        );
      case 3:
        return GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _giftItem(Icons.card_giftcard, '鲜花'),
            _giftItem(Icons.favorite, '爱心'),
            _giftItem(Icons.star, '星星'),
            _giftItem(Icons.auto_awesome, '魔法'),
            _giftItem(Icons.emoji_events, '奖杯'),
            _giftItem(Icons.music_note, '音乐'),
            _giftItem(Icons.cake, '蛋糕'),
            _giftItem(Icons.palette, '艺术'),
          ],
        );
      default:
        return Center(
          child: Text('暂无内容', style: TextStyle(fontSize: 14, color: context.vita.subText)),
        );
    }
  }

  Widget _giftItem(IconData icon, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 32, color: Colors.grey),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _SliverTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverTabDelegate({required this.child});

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _SliverTabDelegate oldDelegate) => child != oldDelegate.child;
}
