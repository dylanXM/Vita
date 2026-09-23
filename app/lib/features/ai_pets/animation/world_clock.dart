import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 世界时钟：单一 Ticker 驱动所有时间相关动画（背景/小屋/粒子）。
/// 页面不可见时由 TickerMode 自动暂停；reduced motion 下不启动。
class WorldClock extends ChangeNotifier {
  WorldClock({required TickerProvider vsync, bool enabled = true}) {
    _ticker = vsync.createTicker(_onTick);
    if (enabled) _ticker.start();
  }

  static const Duration _cycle = Duration(seconds: 60);
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  /// 0..1 循环时间，驱动云漂移、星星闪烁、粒子等。
  double get worldTime =>
      (_elapsed.inMilliseconds % _cycle.inMilliseconds) / _cycle.inMilliseconds;

  /// 0..1 昼夜进度：0 = 子夜，0.5 = 正午，1 = 子夜。
  double get dayProgress {
    final now = DateTime.now();
    return (now.hour * 60 + now.minute) / (24 * 60);
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    notifyListeners();
  }

  void pause() => _ticker.stop();

  void resume() => _ticker.start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
