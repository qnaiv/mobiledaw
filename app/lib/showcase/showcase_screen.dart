// ショーケースモード（案2：ノートレイン）。再生専用の全画面表示で、編集UIは出さない。
// 録画して動画にする用途。ノートが上から下へ流れ、下部のプレイラインで発光する。
//
// 再生の扱い：
// - 停止中に入ったら開始前パネルを出す。「再生開始」でループ範囲を外し、曲頭からワンスルー再生する。
// - 再生中に入ったらパネルを挟まず即レイン表示。再生・ループ設定には一切触らない。
// - 抜けるときも再生には触らない（アレンジに戻っても再生は続く）。止める操作はコントロール側に分ける。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../arrange/song_controller.dart';
import '../model/project.dart';
import '../music/scale.dart';
import '../ui/theme.dart';
import 'showcase_notes.dart';

/// トラック順の固定パレット（モック承認時の色）
const showcasePalette = [
  Color(0xFFFFB454),
  Color(0xFF39D0C4),
  Color(0xFFFF5D73),
  Color(0xFF8F7BFF),
  Color(0xFFC8F25A),
  Color(0xFF5AA9F2),
  Color(0xFFE879C6),
  Color(0xFF5AD6C0),
];

/// ドラムトラック専用色（パレットと重ねず、形も短いブロックで区別する）
const showcaseDrumColor = Color(0xFFFF7A1A);

/// プレイラインの色
const showcasePlayLineColor = Color(0xFFFF5D73);

/// プレイラインの位置（画面の上から何割か）
const showcasePlayLineRatio = 0.8;

/// 先読み（プレイライン到達の何小節前からノートが見えるか）
const showcaseLookaheadBars = 2;

enum _Phase { panel, countdown, rain, ended }

class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key, required this.song});

  final SongController song;

  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends State<ShowcaseScreen> with SingleTickerProviderStateMixin {
  SongController get song => widget.song;

  /// 再生位置と再生中かどうか。アレンジ画面と同じくフレームごとにエンジンから読む
  final _position = ValueNotifier<int>(0);
  final _playing = ValueNotifier<bool>(false);
  late final Ticker _ticker;

  _Phase _phase = _Phase.panel;

  /// 対象トラック（null = 全トラック）
  int? _trackId;
  bool _countdownEnabled = true;
  ShowcaseNotes _data = const ShowcaseNotes(notes: [], maxLengthTicks: 0, minPitch: 48, maxPitch: 71, totalTicks: 1);

  /// 停止中に入って、こちらからワンスルー再生を始めたか。
  /// 再生中に入った場合は false のまま（ループ含め再生状態に触らない）
  bool _oneThrough = false;

  /// 一時停止した位置（停止ボタンとは別。stop は曲頭へ戻るので seek し直して疑似ポーズにする）
  int? _pausedTick;
  int _prevPos = 0;

  int _count = 3;
  Timer? _countTimer;
  bool _controlsVisible = false;
  Timer? _hideTimer;
  Timer? _wakeAssert;

  @override
  void initState() {
    super.initState();
    _data = flattenShowcaseNotes(song.project, trackId: _trackId);
    if (song.engine.isPlaying) {
      // 再生中に入ったら、パネルもカウントダウンも挟まず即レイン
      _phase = _Phase.rain;
    }
    _position.value = song.engine.positionTicks;
    _playing.value = song.engine.isPlaying;
    _prevPos = _position.value;
    _ticker = createTicker((_) => _onFrame())..start();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(WakelockPlus.enable());
    // 再生側の見張り（PlaybackWakeLock）が一時停止検出で wakelock を落とすことがあるため、
    // この画面が開いている間は定期的に点け直す
    _wakeAssert = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(WakelockPlus.enable()));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countTimer?.cancel();
    _hideTimer?.cancel();
    _wakeAssert?.cancel();
    _position.dispose();
    _playing.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // 再生中ならスリープ防止はコントローラーの見張りに引き継ぐ。止まっていれば落とす
    unawaited(WakelockPlus.disable());
    song.syncWakeLock();
    super.dispose();
  }

  void _onFrame() {
    final pos = song.engine.positionTicks;
    final playing = song.engine.isPlaying;
    _position.value = pos;
    _playing.value = playing;
    if (_oneThrough && _phase == _Phase.rain && playing) {
      // ワンスルー再生の終わり：エンジンは曲全体をループするので、位置の巻き戻りで検出する
      final total = _data.totalTicks;
      if (_prevPos >= total - ticksPerBeat && pos < _prevPos - ticksPerBeat) {
        _prevPos = pos;
        _finish();
        return;
      }
    }
    _prevPos = pos;
  }

  // ---- 再生の開始・終了 -------------------------------------------------------

  void _startPressed() {
    if (_countdownEnabled) {
      setState(() {
        _phase = _Phase.countdown;
        _count = 3;
      });
      _countTimer?.cancel();
      _countTimer = Timer.periodic(const Duration(milliseconds: 750), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_count <= 1) {
          t.cancel();
          _beginOneThrough();
        } else {
          setState(() => _count--);
        }
      });
    } else {
      _beginOneThrough();
    }
  }

  void _cancelCountdown() {
    _countTimer?.cancel();
    setState(() => _phase = _Phase.panel);
  }

  /// 停止中からの開始：ループ範囲を外し、曲頭から1回だけ通す（録画用途）
  void _beginOneThrough() {
    song.clearLoopRange();
    song.rewind();
    if (!song.engine.isPlaying) song.togglePlay();
    _oneThrough = true;
    _pausedTick = null;
    _prevPos = 0;
    setState(() {
      _phase = _Phase.rain;
      _controlsVisible = false;
    });
  }

  /// 曲の終わり（ワンスルー検出）または停止ボタン：再生を止めてタイトルカードを出す
  void _finish() {
    song.engine.stopPlayback();
    _oneThrough = false;
    _pausedTick = null;
    _hideTimer?.cancel();
    setState(() {
      _phase = _Phase.ended;
      _controlsVisible = false;
    });
  }

  /// 一時停止：stop は曲頭へ戻るので、位置を覚えて seek し直す
  void _pause() {
    final pos = song.engine.positionTicks;
    song.engine.stopPlayback();
    song.engine.seek(pos);
    _pausedTick = pos;
    _showControls(autoHide: false);
    setState(() {});
  }

  void _resume() {
    final pos = _pausedTick;
    if (pos != null) song.engine.seek(pos);
    song.engine.play();
    song.syncWakeLock();
    _pausedTick = null;
    _prevPos = song.engine.positionTicks;
    _showControls();
    setState(() {});
  }

  // ---- コントロールの表示 ------------------------------------------------------

  void _showControls({bool autoHide = true}) {
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
    if (autoHide && _pausedTick == null) {
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _onTapRain() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _selectTrack(int? trackId) {
    setState(() {
      _trackId = trackId;
      _data = flattenShowcaseNotes(song.project, trackId: trackId);
    });
    if (_phase == _Phase.rain) _showControls();
  }

  // ---- 画面 -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = song.project;
    return Scaffold(
      backgroundColor: DawColors.background,
      body: Stack(
        children: [
          // レイン本体（パネルの裏でも位置 0 の静止画として見せる）
          Positioned.fill(child: _rain()),
          if (_phase == _Phase.panel) _panel(p),
          if (_phase == _Phase.countdown) _countdownOverlay(),
          if (_phase == _Phase.rain) _progress(p),
          if (_phase == _Phase.rain) _controlsOverlay(p),
          if (_phase == _Phase.ended) _endCard(p),
        ],
      ),
    );
  }

  Widget _rain() {
    return ValueListenableBuilder<int>(
      valueListenable: _position,
      builder: (context, pos, _) {
        final displayPos = switch (_phase) {
          _Phase.ended => _data.totalTicks,
          _Phase.panel || _Phase.countdown => song.engine.isPlaying ? pos : 0,
          _Phase.rain => _pausedTick ?? pos,
        };
        return CustomPaint(
          painter: _RainPainter(
            data: _data,
            positionTick: displayPos,
            ticksPerBar: song.project.ticksPerBar,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _panel(ProjectData p) {
    return ColoredBox(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  '${p.tempo.round()} BPM ・ ${noteName(p.keyRoot + 60)} ${p.scale}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DawColors.muted),
                ),
                const SizedBox(height: 24),
                const Text('流すトラック', style: TextStyle(color: DawColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                _trackChips(),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('カウントダウン（3・2・1）'),
                  subtitle: const Text('録画を始めてから再生が始まるまでに間を作ります'),
                  value: _countdownEnabled,
                  onChanged: (v) => setState(() => _countdownEnabled = v),
                ),
                if (song.hasLoopRange)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('ループ範囲は外して、曲の頭から1回だけ再生します',
                        style: TextStyle(color: DawColors.muted, fontSize: 12)),
                  ),
                if (_data.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('選んだトラックにはノートがありません', style: TextStyle(color: DawColors.muted, fontSize: 12)),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _startPressed,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ショーケース再生'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('戻る')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _countdownOverlay() {
    return ColoredBox(
      color: Colors.black38,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_count', style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold)),
            TextButton(onPressed: _cancelCountdown, child: const Text('やめる')),
          ],
        ),
      ),
    );
  }

  Widget _progress(ProjectData p) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 12,
      child: ValueListenableBuilder<int>(
        valueListenable: _position,
        builder: (context, pos, _) {
          final shown = _pausedTick ?? pos;
          final total = _data.totalTicks;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: total > 0 ? (shown / total).clamp(0, 1).toDouble() : 0,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFFFFB454),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${showcaseClock(shown, p.tempo)} / ${showcaseClock(total, p.tempo)}',
                style: const TextStyle(fontSize: 11, color: DawColors.muted),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controlsOverlay(ProjectData p) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTapRain,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: ColoredBox(
              color: Colors.black26,
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        // 抜ける：再生には触らない
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('抜ける'),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: _playing,
                      builder: (context, playing, _) {
                        final paused = !playing && _pausedTick != null;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 64,
                              icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                              onPressed: playing ? _pause : (paused ? _resume : null),
                            ),
                            const SizedBox(width: 8),
                            // 停止：曲を止めてタイトルカードへ（抜けるとは別）
                            IconButton(
                              iconSize: 40,
                              icon: const Icon(Icons.stop_circle_outlined),
                              onPressed: _finish,
                            ),
                          ],
                        );
                      },
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 44),
                      child: _trackChips(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endCard(ProjectData p) {
    return ColoredBox(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(p.title,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text('${p.tempo.round()} BPM ・ ${noteName(p.keyRoot + 60)} ${p.scale}',
                  style: const TextStyle(color: DawColors.muted)),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(onPressed: _beginOneThrough, icon: const Icon(Icons.replay), label: const Text('もう一度')),
                  const SizedBox(width: 12),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('抜ける')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackChips() {
    final tracks = song.project.tracks;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('全トラック', _trackId == null, () => _selectTrack(null)),
          for (var i = 0; i < tracks.length; i++)
            _chip(
              tracks[i].name,
              _trackId == tracks[i].id,
              () => _selectTrack(tracks[i].id),
              color: tracks[i].isKit ? showcaseDrumColor : showcasePalette[i % showcasePalette.length],
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? (color ?? DawColors.accent) : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : Colors.white24),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, color: selected ? Colors.black : DawColors.text, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }
}

/// ノートレインの描画。位置が変わったフレームだけ描き直し、可視範囲のノートだけを描く
class _RainPainter extends CustomPainter {
  _RainPainter({required this.data, required this.positionTick, required this.ticksPerBar});

  final ShowcaseNotes data;
  final int positionTick;
  final int ticksPerBar;

  @override
  void paint(Canvas canvas, Size size) {
    final playLineY = size.height * showcasePlayLineRatio;
    final lookaheadTicks = ticksPerBar * showcaseLookaheadBars;
    final pxPerTick = playLineY / lookaheadTicks;
    final tailTicks = ((size.height - playLineY) / pxPerTick).ceil();

    // 音程レーンの目安：C の音に薄い縦線
    final span = data.maxPitch - data.minPitch + 1;
    final laneW = size.width / span;
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var pitch = data.minPitch; pitch <= data.maxPitch; pitch++) {
      if (pitch % 12 != 0) continue;
      final x = (pitch - data.minPitch) * laneW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), guide);
    }

    final window = showcaseWindow(data.notes, data.maxLengthTicks, positionTick - tailTicks, positionTick + lookaheadTicks);
    final active = <RainNote>[];
    for (final n in window) {
      if (n.startTick <= positionTick && positionTick < n.endTick) {
        active.add(n);
      } else {
        _drawNote(canvas, n, size, playLineY, pxPerTick, laneW, tailTicks, glow: false);
      }
    }
    for (final n in active) {
      _drawNote(canvas, n, size, playLineY, pxPerTick, laneW, tailTicks, glow: true);
    }

    // プレイライン
    final line = Paint()
      ..color = showcasePlayLineColor.withValues(alpha: 0.3)
      ..strokeWidth = 7;
    canvas.drawLine(Offset(0, playLineY), Offset(size.width, playLineY), line);
    line
      ..color = showcasePlayLineColor
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, playLineY), Offset(size.width, playLineY), line);
  }

  void _drawNote(Canvas canvas, RainNote n, Size size, double playLineY, double pxPerTick, double laneW, int tailTicks,
      {required bool glow}) {
    final color = n.drum ? showcaseDrumColor : showcasePalette[n.trackIndex % showcasePalette.length];
    // 頭（start）が下、尾（end）が上。start がプレイラインに達したときに鳴る
    var yTop = playLineY - (n.endTick - positionTick) * pxPerTick;
    final yBottom = playLineY - (n.startTick - positionTick) * pxPerTick;
    if (n.drum) {
      // ドラムは長くても半拍ぶんの短いブロックにする
      final maxH = ticksPerBeat * 0.5 * pxPerTick;
      if (yBottom - yTop > maxH) yTop = yBottom - maxH;
    }
    if (yBottom < -4 || yTop > size.height + 4) return;
    final x = (n.pitch - data.minPitch) * laneW;
    final w = laneW < 4 ? 2.0 : laneW - 2;
    final rect = RRect.fromRectAndRadius(Rect.fromLTRB(x + 1, yTop, x + 1 + w, yBottom), const Radius.circular(3));

    var alpha = 0.5 + 0.5 * n.velocity.clamp(0, 1);
    if (n.endTick <= positionTick) {
      // 鳴り終わったノートは下へ流れながら薄くなる
      final gone = (positionTick - n.endTick) / (tailTicks > 0 ? tailTicks : 1);
      alpha *= (1 - gone.clamp(0, 1) * 0.8);
    }
    if (glow) {
      final glowPaint = Paint()..color = color.withValues(alpha: 0.4);
      canvas.drawRRect(rect.inflate(3.5), glowPaint);
    }
    canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: alpha.clamp(0, 1).toDouble()));
    if (glow) {
      // 鳴り始めの瞬間は白く光る
      final sinceStart = positionTick - n.startTick;
      final flashLen = ticksPerBeat ~/ 2;
      if (sinceStart >= 0 && sinceStart < flashLen) {
        final a = (1 - sinceStart / flashLen) * 0.75;
        canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: a));
      }
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.positionTick != positionTick || old.data != data || old.ticksPerBar != ticksPerBar;
}
