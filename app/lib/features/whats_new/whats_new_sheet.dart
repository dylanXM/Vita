import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../../core/theme.dart';

class WhatsNewSheet extends StatefulWidget {
  const WhatsNewSheet({super.key, required this.campaign});
  final WhatsNewCampaignContent campaign;

  static Future<void> show(
      BuildContext context, WhatsNewCampaignContent campaign) {
    AnalyticsService.to
        .track('whats_new_impression', category: 'updates', properties: {
      'campaign_id': campaign.id,
      'page_count': campaign.pages.length,
    });
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => WhatsNewSheet(campaign: campaign),
    );
  }

  @override
  State<WhatsNewSheet> createState() => _WhatsNewSheetState();
}

class _WhatsNewSheetState extends State<WhatsNewSheet> {
  final _controller = PageController();
  int _index = 0;

  Future<void> _action(WhatsNewContentPage page) async {
    AnalyticsService.to
        .track('whats_new_cta_clicked', category: 'updates', properties: {
      'campaign_id': widget.campaign.id,
      'page_id': page.id,
      'action': page.ctaAction,
    });
    switch (page.ctaAction) {
      case 'next':
        if (_index < widget.campaign.pages.length - 1) {
          await _controller.nextPage(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic);
          return;
        }
        break;
      case 'route':
        Navigator.of(context).pop();
        if (page.ctaValue.startsWith('/')) Get.toNamed(page.ctaValue);
        return;
      case 'url':
        final uri = Uri.tryParse(page.ctaValue);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.campaign.pages;
    final current = pages[_index];
    final cta = current.ctaLabel.resolve();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.78,
          color: context.vita.surface.withValues(alpha: 0.94),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      Text('whatsNew.title'.tr, style: context.vita.title),
                      const Spacer(),
                      IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, color: context.vita.text)),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                Divider(height: 0.5, color: context.vita.divider),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (value) {
                      setState(() => _index = value);
                      AnalyticsService.to.track('whats_new_page_viewed',
                          category: 'updates',
                          properties: {
                            'campaign_id': widget.campaign.id,
                            'page_index': value,
                            'page_id': pages[value].id,
                          });
                    },
                    itemBuilder: (_, i) => _UpdatePage(page: pages[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pages.length > 1) ...[
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                                pages.length,
                                (i) => Container(
                                      width: i == _index ? 20 : 6,
                                      height: 3,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      color: i == _index
                                          ? context.vita.green
                                          : context.vita.divider,
                                    ))),
                        const SizedBox(height: 14),
                      ],
                      ElevatedButton(
                          onPressed: () => _action(current),
                          child: Text(cta.isNotEmpty
                              ? cta
                              : (_index == pages.length - 1
                                  ? 'whatsNew.done'.tr
                                  : 'onboarding.next'.tr))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdatePage extends StatelessWidget {
  const _UpdatePage({required this.page});
  final WhatsNewContentPage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Container(
              width: double.infinity,
              color: context.vita.pageBg,
              child: page.imageUrl.trim().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: page.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                          Icons.auto_awesome_outlined,
                          size: 56,
                          color: context.vita.green))
                  : Icon(Icons.auto_awesome_outlined,
                      size: 56, color: context.vita.green),
            ),
          ),
          const SizedBox(height: 22),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(page.title.resolve(), style: context.vita.pageTitle)),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(page.body.resolve(),
                  style: TextStyle(
                      color: context.vita.subText,
                      fontSize: 15,
                      height: 1.55))),
        ],
      ),
    );
  }
}
