import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/sound/widgets/param_knob.dart';
import 'package:mobiledaw/sound/widgets/segment_chips.dart';

// Phase 3 の共通部品（ノブ／セグメント）のスモークテスト。
void main() {
  testWidgets('ノブを上へドラッグすると値が増える', (tester) async {
    var value = 0.5;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ParamKnob(
            label: 'テスト',
            valueText: value.toStringAsFixed(2),
            unit: value,
            color: Colors.red,
            onChanged: (u) => setState(() => value = u),
          ),
        ),
      ),
    ));
    final dial = find.descendant(of: find.byType(ParamKnob), matching: find.byType(GestureDetector));
    await tester.drag(dial, const Offset(0, -60)); // 60px 上 = +0.3
    await tester.pump();
    expect(value, closeTo(0.8, 0.05));
    await tester.drag(dial, const Offset(0, 300)); // 下へ大きく → 0 に張り付く
    await tester.pump();
    expect(value, closeTo(0.0, 0.02));
    await tester.pump(const Duration(milliseconds: 400)); // ダブルタップ判定のタイマーを流す
  });

  testWidgets('ノブのダブルタップでリセットが呼ばれる', (tester) async {
    var resets = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParamKnob(
          label: 'テスト',
          valueText: '0.50',
          unit: 0.5,
          color: Colors.red,
          onChanged: (_) {},
          onReset: () => resets++,
        ),
      ),
    ));
    final dial = find.descendant(of: find.byType(ParamKnob), matching: find.byType(GestureDetector));
    await tester.tap(dial);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(dial);
    await tester.pump();
    expect(resets, 1);
    await tester.pump(const Duration(milliseconds: 400)); // 判定タイマーを流す
  });

  testWidgets('セグメントチップをタップすると値が返る', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SegmentChips(
          options: const [(0, '全体を這う'), (1, '曲位置に同期'), (2, '狭いループ')],
          selected: 0,
          color: Colors.teal,
          onSelected: (v) => picked = v,
        ),
      ),
    ));
    await tester.tap(find.text('狭いループ'));
    expect(picked, 2);
  });
}
