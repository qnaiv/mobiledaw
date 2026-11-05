import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/piano_roll/automation_params.dart';

ClipData _clip(List<AutomationLaneData> lanes) =>
    ClipData(id: 1, trackId: 1, lengthTicks: 3840, notes: const [], automation: lanes);

void main() {
  group('automationParamFor', () {
    test('gain はトラック音量（仮想 ID 48、0〜2）', () {
      final p = automationParamFor('gain');
      expect(p, isNotNull);
      expect(p!.id, 48);
      expect(p.min, 0);
      expect(p.max, 2);
      expect(p.toUnit(1), 0.5);
    });

    test('cutoffHz はログ目盛り', () {
      final p = automationParamFor('cutoffHz')!;
      expect(p.toUnit(20), 0);
      expect(p.toUnit(20000), 1);
      expect(p.toUnit(632.5), closeTo(0.5, 0.01)); // 幾何平均あたりが真ん中
      expect(p.fromUnit(0.5), closeTo(632.5, 1));
    });

    test('知らないキーは null', () {
      expect(automationParamFor('noSuchParam'), isNull);
    });

    test('代表6種は gain から始まる', () {
      expect(
        automationTargets.map((p) => p.key),
        ['gain', 'cutoffHz', 'wtPos', 'masterGain', 'reverb', 'delay'],
      );
    });
  });

  group('automationValueAt', () {
    final pts = [(480, 0.2), (1440, 1.0), (2400, 0.4)];

    test('最初の点より前は未確定（null）', () {
      expect(automationValueAt(pts, 0), isNull);
      expect(automationValueAt(pts, 479), isNull);
      expect(automationValueAt(const [], 0), isNull);
    });

    test('点の上ではその値、間は直線、最後より後は最後の値', () {
      expect(automationValueAt(pts, 480), 0.2);
      expect(automationValueAt(pts, 960), closeTo(0.6, 1e-9));
      expect(automationValueAt(pts, 1440), 1.0);
      expect(automationValueAt(pts, 9999), 0.4);
    });
  });

  group('automationSegment', () {
    final pts = [(480, 0.2), (1440, 1.0), (2400, 0.4)];

    test('最初の点より前の範囲は空', () {
      expect(automationSegment(pts, 0, 240), isEmpty);
    });

    test('両端は補間した値でつながる', () {
      final seg0 = automationSegment(pts, 0, 960);
      expect(seg0.length, 2);
      expect(seg0[0], (480, 0.2));
      expect(seg0[1].$1, 960);
      expect(seg0[1].$2, closeTo(0.6, 1e-9));
      final seg = automationSegment(pts, 960, 1920);
      expect(seg.first.$1, 960);
      expect(seg.first.$2, closeTo(0.6, 1e-9));
      expect(seg[1], (1440, 1.0));
      expect(seg.last.$1, 1920);
      expect(seg.last.$2, closeTo(0.7, 1e-9));
    });
  });

  group('コピペの計画', () {
    test('コピー→別クリップへ貼り付け：レーンが移り、貼り先だけのレーンは消える', () {
      final src = _clip([
        const AutomationLaneData(param: 'gain', points: [(0, 0.0), (3840, 1.0)]),
        const AutomationLaneData(param: 'cutoffHz', points: [(0, 800.0)]),
      ]);
      final clipboard = copyAutomationLanes(src);
      final dst = _clip([
        const AutomationLaneData(param: 'reverb', points: [(0, 0.3)]),
        const AutomationLaneData(param: 'gain', points: [(0, 0.9)]),
      ]);
      final plan = automationPastePlan(current: dst.automation, clipboard: clipboard);
      final byId = {for (final (id, points) in plan) id: points};
      expect(byId[automationParamFor('reverb')!.id], isEmpty); // 差し替えで消える
      expect(byId[48], [(0, 0.0), (3840, 1.0)]); // gain はコピー元の値に
      expect(byId[automationParamFor('cutoffHz')!.id], [(0, 800.0)]);
    });

    test('コピーは元をあとで触っても影響されない', () {
      final points = <(int, double)>[(0, 0.5)];
      final src = _clip([AutomationLaneData(param: 'gain', points: points)]);
      final copy = copyAutomationLanes(src);
      points.add((960, 1.0)); // 元の点リストを増やしても、コピーには影響しない
      expect(copy.first.points, [(0, 0.5)]);
    });

    test('レーン無しクリップへの貼り付けも計画できる', () {
      final clipboard = copyAutomationLanes(_clip([
        const AutomationLaneData(param: 'wtPos', points: [(0, 0.25), (1920, 0.75)]),
      ]));
      final plan = automationPastePlan(current: const [], clipboard: clipboard);
      expect(plan.length, 1);
      expect(plan.single.$1, automationParamFor('wtPos')!.id);
      expect(plan.single.$2, [(0, 0.25), (1920, 0.75)]);
    });

    test('消去の計画は全レーンを空にする', () {
      final plan = automationClearPlan([
        const AutomationLaneData(param: 'gain', points: [(0, 1.0)]),
        const AutomationLaneData(param: 'delay', points: [(0, 0.2)]),
      ]);
      expect(plan.length, 2);
      expect(plan.every((op) => op.$2.isEmpty), isTrue);
    });

    test('ID に直せないキーは計画から外れる', () {
      final plan = automationPastePlan(
        current: const [],
        clipboard: [const AutomationLaneData(param: 'unknownKey', points: [(0, 1.0)])],
      );
      expect(plan, isEmpty);
    });
  });
}
