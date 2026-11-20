// FX 詳細画面の静的ビジュアル（バッファと粒・EQ カーブ・減衰カーブなど）。
// すべてパラメータ連動の概念図で、実音声の解析ではない。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 決定的な疑似乱数（同じ種からは同じ散布になるように）
class _Lcg {
  _Lcg(int seed) : _s = (seed * 2654435761) & 0x7FFFFFFF;

  int _s;

  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s / 0x7FFFFFFF;
  }
}

/// 素材が無いときの見本波形（なだらかな山並み）
List<double> pseudoPeaks(int seed, [int n = 120]) {
  final rng = _Lcg(seed == 0 ? 1 : seed);
  final raw = [for (var i = 0; i < n; i++) rng.next()];
  return [
    for (var i = 0; i < n; i++)
      ((raw[math.max(0, i - 1)] + raw[i] * 2 + raw[math.min(n - 1, i + 1)]) / 4) *
          (0.3 + 0.7 * (0.5 + 0.5 * math.sin(i / n * math.pi)))
  ];
}

/// 波形バー＋読み位置まわりに散る粒のドット（グラニュラーの概念図）
class BufferGrainPainter extends CustomPainter {
  const BufferGrainPainter({
    required this.peaks,
    required this.positionUnit,
    required this.spray,
    required this.densityUnit,
    required this.sizeUnit,
    required this.texture,
    required this.color,
    required this.dim,
    this.seed = 7,
  });

  final List<double> peaks;

  /// 読み窓の中心（0〜1）
  final double positionUnit;

  /// 散らばり 0〜1
  final double spray;

  /// 粒の数 0〜1
  final double densityUnit;

  /// 粒の大きさ 0〜1
  final double sizeUnit;

  /// 質感 0〜1（高いほどドットが柔らかく溶ける）
  final double texture;
  final Color color;
  final Color dim;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = dim.withValues(alpha: 0.3)..strokeWidth = 1);
    if (peaks.isEmpty) return;
    final winHalf = math.max(0.05, spray * 0.45);
    final winL = (positionUnit - winHalf).clamp(0.0, 1.0);
    final winR = (positionUnit + winHalf).clamp(0.0, 1.0);
    // 読み窓の帯
    canvas.drawRect(
        Rect.fromLTRB(winL * size.width, 4, winR * size.width, size.height - 4),
        Paint()..color = color.withValues(alpha: 0.10));
    // 波形バー
    final barW = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final x = i / peaks.length;
      final inWin = x >= winL && x <= winR;
      final h = math.max(1.5, peaks[i] * (mid - 6));
      canvas.drawLine(
          Offset(i * barW + barW * 0.5, mid - h),
          Offset(i * barW + barW * 0.5, mid + h),
          Paint()
            ..color = (inWin ? color : dim).withValues(alpha: inWin ? 0.85 : 0.45)
            ..strokeWidth = math.max(1.0, barW * 0.6));
    }
    // 粒のドット
    final rng = _Lcg(seed);
    final count = (6 + densityUnit * 30).round();
    for (var i = 0; i < count; i++) {
      final gx = (positionUnit + (rng.next() * 2 - 1) * winHalf).clamp(0.01, 0.99);
      final gy = 0.12 + rng.next() * 0.76;
      final r = (1.4 + sizeUnit * 3.6) * (0.6 + rng.next() * 0.5);
      final alpha = (0.75 - texture * 0.35) * (0.45 + rng.next() * 0.55);
      canvas.drawCircle(Offset(gx * size.width, gy * size.height), r,
          Paint()..color = color.withValues(alpha: alpha.clamp(0.1, 0.95)));
    }
  }

  @override
  bool shouldRepaint(BufferGrainPainter old) =>
      old.peaks != peaks ||
      old.positionUnit != positionUnit ||
      old.spray != spray ||
      old.densityUnit != densityUnit ||
      old.sizeUnit != sizeUnit ||
      old.texture != texture ||
      old.seed != seed;
}

/// 実波形（または見本）のバー表示。開始位置のマーカー付き（サンプラー用）
class WaveformPeaksPainter extends CustomPainter {
  const WaveformPeaksPainter({required this.peaks, required this.color, required this.dim, this.startUnit});

  final List<double> peaks;
  final Color color;
  final Color dim;

  /// 再生開始位置 0〜1（null なら出さない）
  final double? startUnit;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = dim.withValues(alpha: 0.3)..strokeWidth = 1);
    if (peaks.isEmpty) return;
    final barW = size.width / peaks.length;
    for (var i = 0; i < peaks.length; i++) {
      final h = math.max(1.5, peaks[i] * (mid - 6));
      final beforeStart = startUnit != null && i / peaks.length < startUnit!;
      canvas.drawLine(
          Offset(i * barW + barW * 0.5, mid - h),
          Offset(i * barW + barW * 0.5, mid + h),
          Paint()
            ..color = (beforeStart ? dim : color).withValues(alpha: beforeStart ? 0.4 : 0.85)
            ..strokeWidth = math.max(1.0, barW * 0.6));
    }
    if (startUnit != null) {
      final x = startUnit!.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(Offset(x, 3), Offset(x, size.height - 3),
          Paint()..color = color..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(WaveformPeaksPainter old) => old.peaks != peaks || old.startUnit != startUnit;
}

double _smooth(double x) => x <= 0 ? 0 : (x >= 1 ? 1 : x * x * (3 - 2 * x));

/// dart:math に無い tanh の代替
double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// 3バンド EQ の応答カーブ（横軸は 20Hz〜20kHz の対数）
class EqCurvePainter extends CustomPainter {
  const EqCurvePainter({
    required this.lowDb,
    required this.midDb,
    required this.highDb,
    required this.lowUnit,
    required this.midUnit,
    required this.midQ,
    required this.highUnit,
    required this.color,
    required this.dim,
  });

  final double lowDb, midDb, highDb;

  /// 各バンドの周波数位置（対数軸の 0〜1）
  final double lowUnit, midUnit, highUnit;

  /// 中音の Q（0.4〜6）
  final double midQ;
  final Color color;
  final Color dim;

  double _response(double x) {
    double logRatio(double unit) => (x - unit) * math.log(1000) / math.ln2; // オクターブ差
    final tLow = logRatio(lowUnit);
    final tMid = logRatio(midUnit);
    final tHigh = logRatio(highUnit);
    final low = lowDb * (1 - _smooth((tLow + 1.2) / 2.4));
    final mid = midDb * math.exp(-math.pow(tMid * (0.55 + midQ * 0.5), 2));
    final high = highDb * _smooth((tHigh + 1.2) / 2.4);
    return low + mid + high;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), Paint()..color = dim.withValues(alpha: 0.4)..strokeWidth = 1);
    const steps = 140;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final db = _response(x).clamp(-20.0, 20.0);
      final px = x * size.width;
      final py = midY - db / 20 * (midY - 6);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, midY)
      ..lineTo(0, midY)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(EqCurvePainter old) =>
      old.lowDb != lowDb || old.midDb != midDb || old.highDb != highDb || old.lowUnit != lowUnit || old.midUnit != midUnit || old.midQ != midQ || old.highUnit != highUnit;
}

/// リバーブの減衰カーブ（size で尾の長さ、level で高さ）。
/// shimmer のときは上へ漂う粒も描く
class DecayCurvePainter extends CustomPainter {
  const DecayCurvePainter({required this.sizeUnit, required this.level, required this.color, required this.dim, this.shimmer = false});

  /// 広さ 0〜1
  final double sizeUnit;

  /// 量 0〜1
  final double level;
  final Color color;
  final Color dim;
  final bool shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 5;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    final amp = math.max(0.04, level) * (size.height - 14);
    final k = 7.5 - 5.6 * sizeUnit;
    double yAt(double x) => amp * math.exp(-x * k) * (0.9 + 0.1 * math.sin(x * 40));
    const steps = 120;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final px = x * size.width;
      final py = base - yAt(x);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, base)
      ..lineTo(0, base)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    if (shimmer) {
      // オクターブ上のきらめきが上へ漂う
      final rng = _Lcg(31);
      for (var i = 0; i < 14; i++) {
        final x = 0.08 + rng.next() * 0.88;
        final lift = rng.next() * 0.45;
        final py = base - yAt(x) * (1 + lift) - 3;
        if (py < 2) continue;
        canvas.drawCircle(Offset(x * size.width, py), 1.6 + rng.next() * 1.6,
            Paint()..color = color.withValues(alpha: 0.35 + rng.next() * 0.5));
      }
    }
  }

  @override
  bool shouldRepaint(DecayCurvePainter old) => old.sizeUnit != sizeUnit || old.level != level || old.shimmer != shimmer;
}

/// コンプの入出力カーブ（しきい値と比から描く静的表示）
class CompCurvePainter extends CustomPainter {
  const CompCurvePainter({required this.thresholdDb, required this.ratio, required this.makeupDb, required this.color, required this.dim});

  final double thresholdDb;
  final double ratio;
  final double makeupDb;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    // 対角の参照線（無圧縮）
    final ref = Paint()
      ..color = dim.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    const dash = 5.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(Offset(x, size.height - x * size.height / size.width),
          Offset(x + dash, size.height - (x + dash) * size.height / size.width), ref);
    }
    // 入力 -60〜0dB → x、出力 -60〜0dB → y
    double outDb(double inDb) {
      final o = inDb <= thresholdDb ? inDb : thresholdDb + (inDb - thresholdDb) / math.max(1.0, ratio);
      return (o + makeupDb).clamp(-60.0, 0.0);
    }

    const steps = 80;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final inDb = -60 + u * 60;
      final px = u * size.width;
      final py = size.height - (outDb(inDb) + 60) / 60 * size.height;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(CompCurvePainter old) => old.thresholdDb != thresholdDb || old.ratio != ratio || old.makeupDb != makeupDb;
}

/// 飽和の伝達カーブ（tanh 型）
class DriveCurvePainter extends CustomPainter {
  const DriveCurvePainter({required this.amount, required this.color, required this.dim});

  final double amount;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    final k = 1 + 4.5 * amount;
    final norm = _tanh(k);
    const steps = 80;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final x = u * 2 - 1;
      final y = _tanh(x * k) / norm;
      final px = u * size.width;
      final py = (1 - (y + 1) / 2) * size.height;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(DriveCurvePainter old) => old.amount != amount;
}

/// ハイパス（ローカット）の応答カーブ
class HighpassCurvePainter extends CustomPainter {
  const HighpassCurvePainter({required this.cutoffUnit, required this.color, required this.dim});

  /// 対数軸の 0〜1
  final double cutoffUnit;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 4;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    final fc = 0.04 + cutoffUnit * 0.92;
    const steps = 120;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final y = 1 / (1 + math.exp(-(x - fc) / 0.055));
      final px = x * size.width;
      final py = base - y * (size.height - 10);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(HighpassCurvePainter old) => old.cutoffUnit != cutoffUnit;
}

/// ビットクラッシュの階段波形（量が多いほど段が粗い）
class SteppedWavePainter extends CustomPainter {
  const SteppedWavePainter({required this.amount, required this.color, required this.dim});

  final double amount;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = dim.withValues(alpha: 0.3)..strokeWidth = 1);
    final levels = math.max(3, (40 * (1 - amount) + 3).round());
    const steps = 160;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final v = math.sin(x * math.pi * 4);
      final q = (v * levels).round() / levels;
      final px = x * size.width;
      final py = mid - q * (mid - 5);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(SteppedWavePainter old) => old.amount != amount;
}

/// テープのワウ（ピッチがうねる波）／コーラスの二重波にも使う
class WowWavePainter extends CustomPainter {
  const WowWavePainter({required this.amount, required this.color, required this.dim, this.secondWave = false});

  /// 揺れの量 0〜1
  final double amount;
  final Color color;
  final Color dim;

  /// もう1本、位相のずれた波を薄く重ねる（コーラス用）
  final bool secondWave;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = dim.withValues(alpha: 0.3)..strokeWidth = 1);
    void draw(double phaseOff, Color c, double width) {
      const steps = 140;
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final y = math.sin(math.pi * 4 * x + amount * 1.6 * math.sin(math.pi * 3 * x) + phaseOff);
        final px = x * size.width;
        final py = mid - y * (mid - 5);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = width);
    }

    if (secondWave) draw(amount * 1.2, dim.withValues(alpha: 0.55), 1.4);
    draw(0, color, 2.2);
  }

  @override
  bool shouldRepaint(WowWavePainter old) => old.amount != amount || old.secondWave != secondWave;
}
