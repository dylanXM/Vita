import 'package:get/get.dart';

/// App translations: English + Simplified Chinese.
///
/// Covers the shell (tabs), the chat list, the Me page and the Settings
/// area. Use `'key'.tr` or `'key'.trParams({'name': ...})` — placeholders
/// are written as `@name`.
class VitaTranslations extends Translations {
  const VitaTranslations();
  @override
  static const Map<String, Map<String, String>> _keys = {
    'en': {
      // Shell tabs.
      'tab.chat': 'Chat',
      'tab.life': 'Life',
      'tab.memories': 'Memories',
      'tab.me': 'Me',
      // Chat list.
      'chat.subtitle': 'Your companions',
      'chat.empty.title': 'No companion yet',
      'chat.empty.sub': 'Create your companion to start the conversation',
      'chat.companion': 'Companion',
      'chat.distant': 'in a distant city',
      // Me page.
      'me.account': 'Account',
      'me.free': 'Free plan',
      'me.plus.title': 'Vita Plus & Premium',
      'me.plus.active': 'Active · @ent',
      'me.plus.unlock': 'Unlock more of her life',
      'me.credits': 'Credits',
      'me.credits.available': '@n available',
      'me.settings': 'Settings',
      'me.version': 'Vita v1.0.0',
      // Common.
      'common.signout': 'Sign out',
      'common.cancel': 'Cancel',
      'signout.title': 'Sign out?',
      'signout.message': 'Your companion will be waiting when you come back.',
      // Settings.
      'settings.title': 'Settings',
      'settings.general': 'General',
      'settings.account': 'Account',
      'lang.title': 'Language',
      'lang.system': 'System default',
      'lang.english': 'English',
      'lang.chinese': 'Simplified Chinese',
      'theme.title': 'Theme',
      'theme.system': 'Follow phone',
      'theme.light': 'Light',
      'theme.dark': 'Dark',
    },
    'zh': {
      'tab.chat': '聊天',
      'tab.life': '生活',
      'tab.memories': '回忆',
      'tab.me': '我的',
      'chat.subtitle': '你的伙伴',
      'chat.empty.title': '还没有伙伴',
      'chat.empty.sub': '创建你的伙伴，开始对话',
      'chat.companion': '伙伴',
      'chat.distant': '在远方城市',
      'me.account': '账户',
      'me.free': '免费版',
      'me.plus.title': 'Vita Plus & Premium',
      'me.plus.active': '已开通 · @ent',
      'me.plus.unlock': '解锁更多她的生活',
      'me.credits': '积分',
      'me.credits.available': '剩余 @n',
      'me.settings': '设置',
      'me.version': 'Vita v1.0.0',
      'common.signout': '退出登录',
      'common.cancel': '取消',
      'signout.title': '退出登录？',
      'signout.message': '你的伙伴会在这里等你回来。',
      'settings.title': '设置',
      'settings.general': '通用',
      'settings.account': '账户',
      'lang.title': '语言',
      'lang.system': '跟随系统',
      // Language names are always shown in their own language.
      'lang.english': 'English',
      'lang.chinese': '简体中文',
      'theme.title': '主题',
      'theme.system': '跟随手机',
      'theme.light': '浅色',
      'theme.dark': '深色',
    },
  };

  @override
  Map<String, Map<String, String>> get keys => _keys;
}
