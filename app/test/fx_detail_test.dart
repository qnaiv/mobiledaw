import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/sound/fx_detail.dart';
import 'package:mobiledaw/sound/sound_params.dart';
import 'package:mobiledaw/sound/widgets/param_knob.dart';
import 'package:mobiledaw/ui/theme.dart';

// Phase 3 の FX 詳細画面：全ユニット種別を Map バックの読み書きで pump し、
// 例外（レイアウト崩れ含む）が出ないことと、ノブ操作で値が変わることを見る。
FxUnitControls _controls(Map<String, double> values, {double tempo = 120}) => FxUnitControls(
      valueOf: (p) => values[p.key] ?? p.def,
      write: (p, v) => values[p.key] = v,
      beginGesture: () {},
      endGesture: () {},
      tempo: tempo,
    );

Map<String, double> _defaults(FxUnitMeta meta) => {for (final p in meta.params) p.key: p.def};

Widget _harness(FxUnitMeta meta, Map<String, double> values) {
  return MaterialApp(
    theme: buildDawTheme(),
    home: Scaffold(
      body: ListView(
        children: [FxUnitDetailBody(meta: meta, controls: _controls(values))],
      ),
    ),
  );
}

void main() {
  for (final meta in fxUnitMetas) {
    testWidgets('詳細 ${meta.type} が例外なく描画できる', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final values = _defaults(meta);
      await tester.pumpWidget(_harness(meta, values));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 「全パラメータ」を開いても崩れない
      await tester.tap(find.text('全パラメータ'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('グラニュラーの大きさノブを回すと値が変わる', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final meta = fxUnitMetaOf('granular')!;
    final values = _defaults(meta);
    await tester.pumpWidget(_harness(meta, values));
    final firstKnob = find.byType(ParamKnob).first;
    final dial = find.descendant(of: firstKnob, matching: find.byType(GestureDetector));
    await tester.drag(dial, const Offset(0, -80));
    await tester.pump();
    expect(values['granularSizeMs'], isNot(equals(120.0)));
    expect(values['granularSizeMs'], greaterThan(120.0));
    await tester.pump(const Duration(milliseconds: 400)); // ダブルタップ判定のタイマーを流す
  });

  testWidgets('ディレイの音価セグメントと TIME 表示', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final meta = fxUnitMetaOf('delay')!;
    final values = _defaults(meta); // delayDiv 既定 = 1（付点8分）
    await tester.pumpWidget(_harness(meta, values));
    // テンポ120 で付点8分 = 750ms
    expect(find.textContaining('750 ms'), findsOneWidget);
    await tester.tap(find.text('8分'));
    await tester.pump();
    expect(values['delayDiv'], 2.0);
  });

  testWidgets('グラニュラーのフリーズをタップで切り替える', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final meta = fxUnitMetaOf('granular')!;
    final values = _defaults(meta);
    await tester.pumpWidget(_harness(meta, values));
    await tester.tap(find.textContaining('フリーズ'));
    await tester.pump();
    expect(values['granularFreeze'], 1.0);
  });
}
