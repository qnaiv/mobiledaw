import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/arrange/wake_lock.dart';

class FakeWakeLock implements WakeLock {
  int enables = 0;
  int disables = 0;

  @override
  void enable() => enables++;

  @override
  void disable() => disables++;
}

void main() {
  test('playback start enables once, stop disables once', () {
    final lock = FakeWakeLock();
    final playing = true;
    final wake = PlaybackWakeLock(lock: lock, isPlaying: () => playing, interval: const Duration(days: 1));
    addTearDown(wake.dispose);

    wake.started();
    wake.started(); // 二重に始めても有効化は1回だけ
    expect(wake.isOn, isTrue);
    expect(lock.enables, 1);
    expect(lock.disables, 0);

    wake.stopped();
    wake.stopped(); // 止まっているときに止めても何もしない
    expect(wake.isOn, isFalse);
    expect(lock.enables, 1);
    expect(lock.disables, 1);
  });

  test('check releases the lock when playback ended on its own', () {
    final lock = FakeWakeLock();
    var playing = true;
    final wake = PlaybackWakeLock(lock: lock, isPlaying: () => playing, interval: const Duration(days: 1));
    addTearDown(wake.dispose);

    wake.started();
    playing = false; // 自然終了（止める操作を通っていない）
    wake.check();
    expect(wake.isOn, isFalse);
    expect(lock.disables, 1);
  });

  test('watchdog releases the lock shortly after playback ends', () async {
    final lock = FakeWakeLock();
    var playing = true;
    final wake = PlaybackWakeLock(lock: lock, isPlaying: () => playing, interval: const Duration(milliseconds: 10));
    addTearDown(wake.dispose);

    wake.started();
    playing = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(wake.isOn, isFalse);
    expect(lock.disables, 1);
  });

  test('check keeps the lock while still playing', () {
    final lock = FakeWakeLock();
    final wake = PlaybackWakeLock(lock: lock, isPlaying: () => true, interval: const Duration(days: 1));
    addTearDown(wake.dispose);

    wake.started();
    wake.check();
    expect(wake.isOn, isTrue);
    expect(lock.disables, 0);
  });
}
