// FX ユニットの詳細画面：種別ごとに最適な部品（ノブ／スライダー／グラフ／
// セグメント／トグル）で組む。読み書きは FxUnitControls 経由にし、
// 実物は SongController から、テストは Map から作れるようにしてある。
// 主要パラメータを専用部品で出し、全パラメータは従来の汎用リストも併記する。
import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'sound_params.dart';
import 'widgets/fx_painters.dart';
import 'widgets/param_knob.dart';
import 'widgets/segment_chips.dart';

/// ユニット詳細の読み書き口（ジェスチャーは Undo のグループ化用）
class FxUnitControls {
  const FxUnitControls({
    required this.valueOf,
    required this.write,
    required this.beginGesture,
    required this.endGesture,
    required this.tempo,
  });

  final double Function(SoundParam p) valueOf;
  final void Function(SoundParam p, double v) write;
  final VoidCallback beginGesture;
  final VoidCallback endGesture;

  /// ディレイの時間表示用（プロジェクトのテンポ）
  final double tempo;
}

class FxUnitDetailBody extends StatelessWidget {
  const FxUnitDetailBody({super.key, required this.meta, required this.controls});

  final FxUnitMeta meta;
  final FxUnitControls controls;

  SoundParam _p(String key) => meta.params.firstWhere((e) => e.key == key);
  double _v(String key) => controls.valueOf(_p(key));

  @override
  Widget build(BuildContext context) {
    final color = meta.color;
    final hero = switch (meta.type) {
      'granular' => _granular(color),
      'eq' => _eq(color),
      'delay' => _delay(color),
      'reverb' => _reverb(color),
      'shimmer' => _shimmer(color),
      'comp' => _comp(color),
      'ott' => _ott(color),
      'tape' => _tape(color),
      'lowcut' => _lowcut(color),
      'saturation' => _saturation(color),
      'chorus' => _chorus(color),
      'bitcrush' => _bitcrush(color),
      'stutter' => _stutter(color),
      _ => const <Widget>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...hero,
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('全パラメータ', style: TextStyle(fontSize: 13, color: DawColors.muted)),
            children: [for (final p in meta.params) _row(p)],
          ),
        ),
      ],
    );
  }

  // ---- 共通の部品 -------------------------------------------------------------

  Widget _viz(CustomPainter painter, {double height = 88}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: DawColors.background,
        border: Border.all(color: DawColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(painter: painter, child: const SizedBox.expand()),
    );
  }

  Widget _knob(String key, String label, Color color, {double size = 62}) {
    final p = _p(key);
    final v = controls.valueOf(p);
    return ParamKnob(
      label: label,
      valueText: p.format(v),
      unit: p.toUnit(v),
      color: color,
      size: size,
      onChangeStart: controls.beginGesture,
      onChanged: (u) => controls.write(p, p.fromUnit(u)),
      onChangeEnd: (_) => controls.endGesture(),
      onReset: () => controls.write(p, p.def),
    );
  }

  Widget _knobRow(List<Widget> knobs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 18, runSpacing: 8, children: knobs),
    );
  }

  Widget _slider(String key, {bool prominent = false, Color? color, String? label}) {
    final p = _p(key);
    final v = controls.valueOf(p);
    if (p.scale == ParamScale.toggle) return _toggleRow(key);
    return SizedBox(
      height: prominent ? 56 : 48,
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(label ?? p.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: prominent ? 13 : 12, fontWeight: prominent ? FontWeight.w700 : FontWeight.w400)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: prominent ? (color ?? DawColors.accent) : null,
                trackHeight: prominent ? 6 : 4,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: prominent ? 11 : 10),
              ),
              child: Slider(
                value: p.toUnit(v),
                onChangeStart: (_) => controls.beginGesture(),
                onChanged: (u) => controls.write(p, p.fromUnit(u)),
                onChangeEnd: (_) => controls.endGesture(),
              ),
            ),
          ),
          GestureDetector(
            onDoubleTap: () => controls.write(p, p.def),
            child: SizedBox(
              width: 64,
              child: Text(p.format(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String key, {String? label}) {
    final p = _p(key);
    final on = controls.valueOf(p) >= 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label ?? p.label, style: const TextStyle(fontSize: 13))),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('オフ')),
              ButtonSegment(value: true, label: Text('オン')),
            ],
            selected: {on},
            onSelectionChanged: (s) => controls.write(p, s.first ? 1 : 0),
          ),
        ],
      ),
    );
  }

  /// 全パラメータ用の汎用行
  Widget _row(SoundParam p) => p.scale == ParamScale.toggle ? _toggleRow(p.key) : _slider(p.key);

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(text, style: const TextStyle(fontSize: 12, color: DawColors.muted)),
      );

  // ---- 種別ごとのレイアウト -----------------------------------------------------

  /// グラニュラーのプリセット行（Phase 2.6）: 選ぶと全パラメータに値が入る
  Widget _granularPresets(Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final preset in fxGranularPresets)
            ActionChip(
              label: Text(preset.name, style: const TextStyle(fontSize: 12)),
              avatar: Icon(Icons.auto_awesome, size: 14, color: color),
              onPressed: () {
                controls.beginGesture();
                for (final e in preset.values.entries) {
                  final p = meta.params.where((x) => x.key == e.key);
                  if (p.isNotEmpty) controls.write(p.first, e.value);
                }
                controls.endGesture();
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _granular(Color color) {
    final pos = _p('granularPositionS');
    return [
      _viz(BufferGrainPainter(
        peaks: pseudoPeaks(13),
        positionUnit: _v('granularPositionS') / pos.max,
        spray: _v('granularSpray'),
        densityUnit: _p('granularDensity').toUnit(_v('granularDensity')),
        sizeUnit: _p('granularSizeMs').toUnit(_v('granularSizeMs')),
        texture: _v('granularTexture'),
        color: color,
        dim: DawColors.muted,
      ), height: 96),
      _granularPresets(color),
      // 主面は音楽的な名前の主要パラメータだけ（濃さ／粒の大きさ／密度／霧／広がり）。
      // 位置・ピッチ・フィードバック等は下の「全パラメータ」で触れる
      _knobRow([
        _knob('granular', '濃さ', color),
        _knob('granularSizeMs', '粒の大きさ', color),
        _knob('granularDensity', '密度', color),
      ]),
      _slider('granularTexture', label: '霧（粒の輪郭と溶け具合）'),
      _slider('granularSpray', label: '広がり（位置の散らばり）'),
      _freezeToggle(color),
    ];
  }

  /// フリーズの大きなトグル（グラニュラー専用）
  Widget _freezeToggle(Color color) {
    final p = _p('granularFreeze');
    final on = controls.valueOf(p) >= 0.5;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => controls.write(p, on ? 0 : 1),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.22) : DawColors.background,
            border: Border.all(color: on ? color : DawColors.line, width: on ? 1.6 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.ac_unit, size: 22, color: on ? color : DawColors.muted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('フリーズ（今の音を凍らせて回す）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text(on ? 'オン' : 'オフ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? color : DawColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _eq(Color color) {
    return [
      _viz(EqCurvePainter(
        lowDb: _v('eqLowDb'),
        midDb: _v('eqMidDb'),
        highDb: _v('eqHighDb'),
        lowUnit: _p('eqLowHz').toUnit(_v('eqLowHz')),
        midUnit: _p('eqMidHz').toUnit(_v('eqMidHz')),
        midQ: _v('eqMidQ'),
        highUnit: _p('eqHighHz').toUnit(_v('eqHighHz')),
        color: color,
        dim: DawColors.muted,
      ), height: 96),
      _knobRow([
        _knob('eqLowDb', '低音', color),
        _knob('eqMidDb', '中音', color),
        _knob('eqHighDb', '高音', color),
      ]),
      _slider('eqLowHz'),
      _slider('eqMidHz'),
      _slider('eqMidQ'),
      _slider('eqHighHz'),
    ];
  }

  List<Widget> _delay(Color color) {
    const names = ['4分', '付点8分', '8分', '16分', '1小節'];
    const beats = [1.0, 1.5, 0.5, 0.25, 4.0];
    final div = _v('delayDiv').round().clamp(0, 4);
    final ms = controls.tempo > 0 ? 60000 / controls.tempo * beats[div] : 0.0;
    final timeText = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)} s' : '${ms.round()} ms';
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(names[div], style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 10),
          Text('TIME $timeText', style: const TextStyle(fontSize: 13, color: DawColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
      _caption('長さ'),
      SegmentChips(
        options: [for (var i = 0; i < names.length; i++) (i, names[i])],
        selected: div,
        color: color,
        onSelected: (v) => controls.write(_p('delayDiv'), v.toDouble()),
      ),
      _knobRow([
        _knob('delay', '量', color),
        _knob('delayFeedback', '繰り返し', color),
      ]),
      _toggleRow('delayPingpong', label: 'ピンポン（左右を交互に跳ねる）'),
    ];
  }

  List<Widget> _reverb(Color color) {
    return [
      _viz(DecayCurvePainter(sizeUnit: _v('reverbSize'), level: _v('reverb'), color: color, dim: DawColors.muted), height: 84),
      _knobRow([
        _knob('reverb', '量', color),
        _knob('reverbSize', '広さ', color),
      ]),
    ];
  }

  List<Widget> _shimmer(Color color) {
    return [
      _viz(DecayCurvePainter(sizeUnit: _v('shimmerSize'), level: _v('shimmer'), color: color, dim: DawColors.muted, shimmer: true),
          height: 84),
      _knobRow([
        _knob('shimmer', '量', color),
        _knob('shimmerSize', '広さ', color),
      ]),
      _caption('きらめき'),
      _slider('shimmerAmount', prominent: true, color: color),
      _slider('shimmerTone'),
    ];
  }

  List<Widget> _comp(Color color) {
    return [
      _viz(CompCurvePainter(
          thresholdDb: _v('compThresholdDb'), ratio: _v('compRatio'), makeupDb: _v('compMakeupDb'), color: color, dim: DawColors.muted),
          height: 92),
      _knobRow([
        _knob('comp', '量', color),
        _knob('compThresholdDb', 'しきい値', color),
        _knob('compRatio', '比', color),
      ]),
      _slider('compAttackMs'),
      _slider('compReleaseMs'),
      _slider('compMakeupDb'),
    ];
  }

  List<Widget> _ott(Color color) {
    return [
      _caption('帯域ごとに音を持ち上げて密度を出す'),
      Center(child: _knob('ott', 'OTT', color, size: 88)),
    ];
  }

  List<Widget> _tape(Color color) {
    return [
      _viz(WowWavePainter(amount: _v('tapeWow'), color: color, dim: DawColors.muted), height: 56),
      _knobRow([
        _knob('tape', '量', color),
        _knob('tapeWow', 'ワウ', color),
        _knob('tapeSat', '太さ', color),
      ]),
      _slider('tapeHiss'),
    ];
  }

  List<Widget> _lowcut(Color color) {
    return [
      _viz(HighpassCurvePainter(cutoffUnit: _p('lowCutHz').toUnit(_v('lowCutHz')), color: color, dim: DawColors.muted), height: 72),
      Center(child: _knob('lowCutHz', 'ローカット', color, size: 88)),
    ];
  }

  List<Widget> _saturation(Color color) {
    return [
      _viz(DriveCurvePainter(amount: _v('saturation'), color: color, dim: DawColors.muted), height: 72),
      Center(child: _knob('saturation', 'サチュレーション', color, size: 88)),
    ];
  }

  List<Widget> _chorus(Color color) {
    return [
      _viz(WowWavePainter(amount: _v('chorus'), color: color, dim: DawColors.muted, secondWave: true), height: 56),
      Center(child: _knob('chorus', 'コーラス', color, size: 88)),
    ];
  }

  List<Widget> _bitcrush(Color color) {
    return [
      _viz(SteppedWavePainter(amount: _v('bitcrush'), color: color, dim: DawColors.muted), height: 56),
      Center(child: _knob('bitcrush', 'ビットクラッシュ', color, size: 88)),
    ];
  }

  List<Widget> _stutter(Color color) {
    const names = ['2分', '4分', '付点8分', '8分', '16分'];
    final div = _v('stutterDiv').round().clamp(0, 4);
    return [
      _caption('繰り返しの長さ'),
      SegmentChips(
        options: [for (var i = 0; i < names.length; i++) (i, names[i])],
        selected: div,
        color: color,
        onSelected: (v) => controls.write(_p('stutterDiv'), v.toDouble()),
      ),
      Center(child: _knob('stutter', 'スタッター', color, size: 88)),
    ];
  }
}
