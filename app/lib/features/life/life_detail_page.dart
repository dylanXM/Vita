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
  final GlobalKey _moreKey = GlobalKey();

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

  /// WeChat-style dark popup anchored to the trailing "more" button.
  Future<void> _openMoreMenu() async {
    final buttonCtx = _moreKey.currentContext;
    if (buttonCtx == null) return;
    final box = buttonCtx.findRenderObject() as RenderBox;
    final buttonRect = box.localToGlobal(Offset.zero) & box.size;
    final screenSize = MediaQuery.of(context).size;

    const menuWidth = 168.0;
    const gap = 8.0;
    // Align the menu's right edge with the button's right edge.
    final menuLeft = screenSize.width -
        menuWidth -
        (screenSize.width - buttonRect.right);
    final menuTop = buttonRect.bottom + gap;
    final triangleCenterX =
        (buttonRect.center.dx - menuLeft).clamp(12.0, menuWidth - 12.0);

    final c = widget.companion;
    final name = c['name'] as String? ?? 'Companion';

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _WeChatPopupMenu(
        menuLeft: menuLeft,
        menuTop: menuTop,
        menuWidth: menuWidth,
        triangleCenterX: triangleCenterX,
        items: [
          _MenuItemData(
            icon: Icons.chat_bubble_outline,
            label: '发起聊天',
            onTap: () => Get.to(
              () => ChatPage(
                  companionId: c['id'] as String, name: name, companion: c),
              transition: Transition.cupertino,
            ),
          ),
          _MenuItemData(
            icon: Icons.card_giftcard,
            label: '送TA礼物',
            onTap: () => setState(() => _tabIndex = 3),
          ),
          const _MenuItemData(
            icon: Icons.edit_outlined,
            label: '修改备注',
            onTap: _noop,
          ),
          _MenuItemData(
            icon: Icons.delete_outline,
            label: '删除',
            onTap: _confirmDelete,
          ),
        ],
        onClose: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
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
            elevation: 0,
            toolbarHeight: 44,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 22),
              onPressed: () => Get.back(),
            ),
            actions: [
              IconButton(
                key: _moreKey,
                icon: const Icon(Icons.more_horiz, color: Colors.black, size: 24),
                onPressed: _openMoreMenu,
              ),
            ],
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
        final habits = c['life_habits'] as String? ?? '';
        final goal = c['life_goal'] as String? ?? '';
        if (habits.isEmpty && goal.isEmpty) {
          return Center(
            child: Text('暂无内容', style: TextStyle(fontSize: 14, color: context.vita.subText)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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

/// A single row in the WeChat-style dark popup menu.
class _MenuItemData {
  const _MenuItemData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

void _noop() {}

/// Upward triangle that points from the dark menu card back at the trigger.
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color, required this.centerX});

  final Color color;
  final double centerX;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    const halfW = 8.0;
    final path = Path()
      ..moveTo(centerX - halfW, size.height)
      ..lineTo(centerX, 0)
      ..lineTo(centerX + halfW, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.centerX != centerX;
}

/// WeChat-inspired dark dropdown: rounded dark card, white icon+label rows,
/// hairline separators inset to the label, and a little arrow pointing at the
/// trigger button. Tapping the barrier or a row dismisses it.
class _WeChatPopupMenu extends StatefulWidget {
  const _WeChatPopupMenu({
    required this.menuLeft,
    required this.menuTop,
    required this.menuWidth,
    required this.triangleCenterX,
    required this.items,
    required this.onClose,
  });

  final double menuLeft;
  final double menuTop;
  final double menuWidth;
  final double triangleCenterX;
  final List<_MenuItemData> items;
  final VoidCallback onClose;

  @override
  State<_WeChatPopupMenu> createState() => _WeChatPopupMenuState();
}

class _WeChatPopupMenuState extends State<_WeChatPopupMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuColor =
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFF7A7E83);
    const foreground = Colors.white;
    final dividerColor = Colors.white.withValues(alpha: 0.22);
    const itemHeight = 48.0;
    const itemHPadding = 20.0;
    const iconSize = 22.0;
    const iconGap = 14.0;
    final dividerIndent = itemHPadding + iconSize + iconGap;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: widget.menuLeft,
              top: widget.menuTop,
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -8),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(
                          size: Size(widget.menuWidth, 8),
                          painter: _TrianglePainter(
                            color: menuColor,
                            centerX: widget.triangleCenterX,
                          ),
                        ),
                        Container(
                          width: widget.menuWidth,
                          decoration: BoxDecoration(
                            color: menuColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < widget.items.length; i++) ...[
                                if (i > 0)
                                  Padding(
                                    padding:
                                        EdgeInsets.only(left: dividerIndent),
                                    child: Container(
                                      height: 0.5,
                                      color: dividerColor,
                                    ),
                                  ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    widget.onClose();
                                    widget.items[i].onTap();
                                  },
                                  child: SizedBox(
                                    height: itemHeight,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: itemHPadding),
                                      child: Row(
                                        children: [
                                          Icon(widget.items[i].icon,
                                              size: iconSize,
                                              color: foreground),
                                          const SizedBox(width: iconGap),
                                          Text(widget.items[i].label,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  color: foreground)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
