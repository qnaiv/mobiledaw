import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// 画面を眠らせないための口（テストでは差し替える）
abstract interface class WakeLock {
  void enable();
  void disable();
}

/// 本番用：wakelock_plus で画面を点けたままにする
class WakelockPlusWakeLock implements WakeLock {
  const WakelockPlusWakeLock();

  @override
  void enable() => unawaited(WakelockPlus.enable());

  @override
  void disable() => unawaited(WakelockPlus.disable());
}

/// 再生中だけ画面を眠らせない。
/// 開始・停止は再生の入口から知らせてもらい、止め忘れ（曲の自然終了や、
/// 他の画面から直接エンジンを止められた場合）に備えて、再生状態を定期的に見直す
class PlaybackWakeLock {
  PlaybackWakeLock({
    required WakeLock lock,
    required bool Function() isPlaying,
    Duration interval = const Duration(milliseconds: 500),
  })  : _lock = lock,
        _isPlaying = isPlaying,
        _interval = interval;

  final WakeLock _lock;
  final bool Function() _isPlaying;
  final Duration _interval;
  Timer? _watch;
  bool _on = false;

  bool get isOn => _on;

  /// 再生が始まった
  void started() {
    if (_on) return;
    _on = true;
    _lock.enable();
    _watch ??= Timer.periodic(_interval, (_) => check());
  }

  /// 再生が止まった
  void stopped() {
    if (!_on) return;
    _on = false;
    _watch?.cancel();
    _watch = null;
    _lock.disable();
  }

  /// 再生状態と食い違っていたら直す（自然終了の検出用。[started] の見張りから呼ばれる）
  void check() {
    if (_on && !_isPlaying()) stopped();
  }

  void dispose() => stopped();
}
