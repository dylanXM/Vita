import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_content_controller.dart';
import '../../core/theme.dart';
import '../../core/token_storage.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  List<OnboardingContentPage> get _pages =>
      AppContentController.to.onboarding?.pages ?? const [];

  Future<void> _finish() async {
    await AppContentController.to.completeOnboarding();
    final token = await TokenStorage.read();
    if (!mounted) return;
    Get.offAllNamed(token == null || token.isEmpty ? '/login' : '/shell');
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Icon(Icons.all_inclusive,
                      color: context.vita.green, size: 30),
                  const Spacer(),
                  TextButton(
                      onPressed: _finish, child: Text('onboarding.skip'.tr)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) =>
                    _OnboardingPanel(page: pages[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        pages.length,
                        (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: i == _index ? 24 : 8,
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              color: i == _index
                                  ? context.vita.green
                                  : context.vita.divider,
                            )),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _next,
                    child: Text(_index == pages.length - 1
                        ? 'onboarding.start'.tr
                        : 'onboarding.next'.tr),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPanel extends StatelessWidget {
  const _OnboardingPanel({required this.page});
  final OnboardingContentPage page;

  IconData get _icon => switch (page.icon) {
        'life' => Icons.wb_sunny_outlined,
        'infinity' => Icons.all_inclusive,
        'memory' => Icons.auto_awesome_outlined,
        _ => Icons.chat_bubble_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: context.vita.surface,
              child: page.imageUrl.trim().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: page.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _IconHero(icon: _icon),
                    )
                  : _IconHero(icon: _icon),
            ),
          ),
          const SizedBox(height: 28),
          Text(page.title.resolve(),
              textAlign: TextAlign.center, style: context.vita.pageTitle),
          const SizedBox(height: 10),
          Text(
            page.body.resolve(),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.vita.subText, fontSize: 15, height: 1.55),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          color: context.vita.greenTint,
          border: Border.all(
              color: context.vita.green.withValues(alpha: 0.22), width: 0.5),
        ),
        child: Icon(icon, size: 68, color: context.vita.green),
      ),
    );
  }
}
