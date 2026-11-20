import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/arrange/channel_strip.dart';
import 'package:mobiledaw/sound/sound_params.dart';
import 'package:mobiledaw/sound/widgets/param_knob.dart';
import 'package:mobiledaw/ui/theme.dart';

// Phase 4 のチャンネルストリップ：コールバック口だけを相手に pump し、
// 表示・フェーダー操作・M/S 切替・メーター減衰の計算を見る。
SoundParam _param(String key) => allSoundParams.firstWhere((e) => e.key == key);

class _FakeStrip {
  double gain = 0.8;
  double pan = 0;
  double rev = 0;
  double dly = 0;
  bool mute = false;
  bool solo = false;
  bool selected = false;
  final ValueNotifier<double> peak = ValueNotifier<double>(0.4);

  Widget build(String name, int color) {
    return ChannelStrip(
      name: name,
      color: Color(color),
      selected: selected,
      dimmed: mute,
      gain: gain,
      pan: pan,
      mute: mute,
      solo: solo,
      sendReverbParam: _param('sendReverb'),
      sendReverb: rev,
      sendDelayParam: _param('sendDelay'),
      sendDelay: dly,
      peak: peak,
      onSelect: () => selected = true,
      onRename: () {},
      onGainChanged: (v) => gain = v,
      onPanChanged: (v) => pan = v,
      onSendChanged: (p, v) {
        if (p.key == 'sendReverb') rev = v;
        if (p.key == 'sendDelay') dly = v;
      },
      onMuteToggle: () => mute = !mute,
      onSoloToggle: () => solo = !solo,
    );
  }
}

Widget _harness(List<Widget> children) {
  return MaterialApp(
    theme: buildDawTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ),
  );
}

void main() {
  testWidgets('複数トラックのストリップが並んで表示される', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final a = _FakeStrip(), b = _FakeStrip(), c = _FakeStrip();
    await tester.pumpWidget(_harness([
      a.build('ドラム', 0xFFF28C38),
      const SizedBox(width: 8),
      b.build('ベース', 0xFF5AA9F2),
      const SizedBox(width: 8),
      c.build('パッド', 0xFFC8F25A),
    ]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('ドラム'), findsOneWidget);
    expect(find.text('ベース'), findsOneWidget);
    expect(find.text('パッド'), findsOneWidget);
    expect(find.byType(VerticalFader), findsNWidgets(3));
    expect(find.byType(PeakMeterBar), findsNWidgets(3));
  });

  testWidgets('フェーダーを上げると gain が増え、下げると減る', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _FakeStrip();
    await tester.pumpWidget(_harness([s.build('ドラム', 0xFFF28C38)]));
    await tester.drag(find.byType(VerticalFader), const Offset(0, -60));
    await tester.pump();
    expect(s.gain, greaterThan(0.8));
    final up = s.gain;
    await tester.drag(find.byType(VerticalFader), const Offset(0, 90));
    await tester.pump();
    expect(s.gain, lessThan(up));
    await tester.pump(const Duration(milliseconds: 400)); // ダブルタップ判定タイマーを流す
  });

  testWidgets('M / S ボタンでミュート・ソロが切り替わる', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _FakeStrip();
    await tester.pumpWidget(_harness([s.build('ドラム', 0xFFF28C38)]));
    await tester.tap(find.text('M'));
    await tester.pump();
    expect(s.mute, isTrue);
    await tester.tap(find.text('S'));
    await tester.pump();
    expect(s.solo, isTrue);
  });

  testWidgets('パンノブを回すと pan が変わる', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = _FakeStrip();
    await tester.pumpWidget(_harness([s.build('ドラム', 0xFFF28C38)]));
    // 最初の ParamKnob がパン
    final knob = find.byType(ParamKnob).first;
    final dial = find.descendant(of: knob, matching: find.byType(GestureDetector));
    await tester.drag(dial, const Offset(0, -60));
    await tester.pump();
    expect(s.pan, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('マスターストリップが表示され、フェーダーで音量が変わる', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    double gain = 3.2;
    final peak = ValueNotifier<double>(0.7);
    await tester.pumpWidget(_harness([
      MasterStrip(gain: gain, peak: peak, onGainChanged: (v) => gain = v),
    ]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('マスター'), findsOneWidget);
    await tester.drag(find.byType(VerticalFader), const Offset(0, -50));
    await tester.pump();
    expect(gain, greaterThan(3.2));
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('メーター表示値は読み値優先で、無音では減衰する', () {
    expect(nextMeterLevel(0.5, 0.1), 0.5); // 大きい読み値が勝つ
    expect(nextMeterLevel(0, 1), closeTo(0.86, 1e-9)); // 無音なら 0.86 倍ずつ落ちる
    expect(nextMeterLevel(0, 0), 0);
    var v = 1.0;
    for (var i = 0; i < 20; i++) {
      v = nextMeterLevel(0, v);
    }
    expect(v, lessThan(0.05)); // 約1秒（20回）でほぼ消える
  });
}
