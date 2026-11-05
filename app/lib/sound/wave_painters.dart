// 音色画面のグラフィック表示（波形・フィルター特性・ADSR）。
// ウェーブテーブルの波形はコア（core/src/wavetable.cpp）と同じ倍音プロファイルで計算する。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [倍音番号, 振幅, 位相] のリスト。コアの tableHarmonics と同じ。
List<(int, double, double)> wtHarmonics(int table, double f) {
  final out = <(int, double, double)>[];
  if (table == 3) {
    // フォルマント（母音 A→E→I→O→U）
    const formants = [
      [7.0, 11.0, 26.0],
      [5.0, 19.0, 26.0],
      [3.0, 23.0, 30.0],
      [5.0, 9.0, 26.0],
      [3.0, 7.0, 24.0],
    ];
    final x = f * 4;
    final seg = math.min(3, x.floor());
    final fr = x - seg;
    for (var h = 1; h <= 32; h++) {
      var a = 0.15 / h;
      for (var i = 0; i < 3; i++) {
        final c = formants[seg][i] * (1 - fr) + formants[seg + 1][i] * fr;
        final d = (h - c) / (i == 0 ? 2.5 : 4.0);
        a += math.exp(-d * d) * (i == 0 ? 1.0 : 0.55);
      }
      out.add((h, a, 0));
    }
    return out;
  }
  for (var h = 1; h <= 32; h++) {
    var a = 0.0;
    var ph = 0.0;
    switch (table) {
      case 1: // 基本（サイン→三角→矩形→のこぎり）
        {
          var sine = 0.0, tri = 0.0, square = 0.0;
          final saw = 0.64 / h;
          if (h == 1) sine = 1;
          if (h % 2 == 1) {
            tri = ((h >> 1) % 2 == 0 ? 1.0 : -1.0) * 0.81 / (h * h);
            square = 1.27 / h;
          }
          final x = f * 3;
          final seg = math.min(2, x.floor());
          final fr = x - seg;
          final shapes = [sine, tri, square, saw];
          a = shapes[seg] * (1 - fr) + shapes[seg + 1] * fr;
        }
      case 2: // 倍音（山が掃引）
        {
          final c = 1 + f * 24;
          final d = (h - c) / 6;
          a = math.exp(-d * d) * 0.9 + (h == 1 ? 0.8 : 0.0) + 0.12 / h;
        }
      case 4: // デジタル（ハッシュで立つ倍音）
        {
          var x = (h * 2654435761) & 0xFFFFFFFF;
          x ^= x >> 13;
          x = (x * 2654435761) & 0xFFFFFFFF;
          final r1 = (x & 0xFFFF) / 65536.0;
          ph = ((x >> 16) & 0xFFFF) / 65536.0;
          if (h == 1) {
            a = 0.9;
          } else {
            a = r1 < 0.15 + f * 0.6 ? 0.8 / h : 0.0;
          }
        }
      case 5: // スペクトルソー（frame で肩が上がり明るく）
        {
          final shoulder = 3 + f * 61;
          final d = h / shoulder;
          a = 0.85 / h / (1 + d * d) + (h == 1 ? 0.35 : 0.0);
        }
      case 6: // パルス（デューティ 0.5→0.08）
        {
          final duty = 0.5 - f * 0.42;
          a = 1.3 * math.sin(math.pi * h * duty) / h;
        }
      case 7: // クワイア（ゆるいフォルマント＋ばらつき）
        {
          var hx = (h * 2654435761) & 0xFFFFFFFF;
          hx ^= hx >> 13;
          final jr = (hx & 0xFFFF) / 65536.0;
          ph = ((hx >> 16) & 0xFFFF) / 65536.0 * 0.5;
          final shift = 0.75 + f * 0.8;
          var acc = 0.2 / h;
          const centers = [4.0, 9.0, 20.0];
          const widths = [2.2, 4.5, 8.0];
          const heights = [1.0, 0.6, 0.35];
          for (var i = 0; i < 3; i++) {
            final d = (h - centers[i] * shift) / widths[i];
            acc += math.exp(-d * d) * heights[i];
          }
          a = acc * (0.85 + 0.3 * jr);
        }
      default:
        a = 0;
    }
    if (a != 0) out.add((h, a, ph));
  }
  return out;
}

double _warpPhase(double phase, int warp, double amount) {
  final a = amount.clamp(0.0, 1.0);
  var p = phase;
  switch (warp) {
    case 1:
      p = phase + 0.159 * a * math.sin(2 * math.pi * phase);
    case 2:
      final k = 0.5 - 0.4 * a;
      p = phase < k ? 0.5 * phase / k : 0.5 + 0.5 * (phase - k) / (1 - k);
    case 3:
      p = phase * (1 + a * 3);
    default:
      return phase;
  }
  return p - p.floorToDouble();
}

double _wtY(List<(int, double, double)> hs, int warp, double warpAmt, double x) {
  final p = _warpPhase(x, warp, warpAmt);
  var v = 0.0;
  for (final (h, a, ph) in hs) {
    v += a * math.sin(2 * math.pi * (h * p + ph));
  }
  return v;
}

/// ウェーブテーブルの波形表示：現在のフレームを太く、前後フレームを薄く重ねる
class WtWavePainter extends CustomPainter {
  const WtWavePainter({required this.table, required this.pos, required this.warp, required this.warpAmt, required this.color, required this.ghost});

  final int table;
  final double pos;
  final int warp;
  final double warpAmt;
  final Color color;
  final Color ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = ghost.withValues(alpha: 0.35)..strokeWidth = 1);
    const steps = 140;
    void drawFrame(double pp, Color c, double width, double yOff) {
      final hs = wtHarmonics(table, pp);
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final y = _wtY(hs, warp, warpAmt, x) * 0.62;
        final px = x * size.width;
        final py = mid - y * (mid - 6) + yOff;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = width);
    }

    for (final off in [-0.24, -0.12, 0.12, 0.24]) {
      drawFrame((pos + off).clamp(0.0, 1.0), ghost.withValues(alpha: 0.3), 1.1, off * 26);
    }
    drawFrame(pos, color, 2.4, 0);
  }

  @override
  bool shouldRepaint(WtWavePainter old) => old.table != table || old.pos != pos || old.warp != warp || old.warpAmt != warpAmt;
}

/// 32フレームの帯のうち現在の位置（音色画面のミニ表示）
class WtStripPainter extends CustomPainter {
  const WtStripPainter({required this.table, required this.pos, required this.color, required this.dim});

  final int table;
  final double pos;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 32;
    final cur = (pos * 31).round();
    for (var i = 0; i < 32; i++) {
      var e = 0.0;
      for (final (_, a, _) in wtHarmonics(table, i / 31)) {
        e += a.abs();
      }
      final h = (4 + math.min(18.0, e * 5.5)).toDouble();
      final paint = Paint()..color = i == cur ? color : dim.withValues(alpha: 0.4 + 0.4 * math.exp(-(i - cur).abs() / 6));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * w + 0.6, size.height - h, w - 1.2, h), const Radius.circular(1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WtStripPainter old) => old.table != table || old.pos != pos;
}

/// アナログの波形表示：ユニゾンの重なりが見える
class AnalogWavePainter extends CustomPainter {
  const AnalogWavePainter({required this.square, required this.unison, required this.color, required this.dim});

  final bool square;
  final int unison;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    const steps = 140;
    final n = unison.clamp(1, 16);
    for (var v = 0; v < n; v++) {
      final off = n == 1 ? 0.0 : (v / (n - 1) - 0.5);
      final center = v == (n >> 1);
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final p = (x * (1 + off * 0.012)) % 1.0;
        final y = square ? (p < 0.5 ? 0.85 : -0.85) : (p * 2 - 1);
        final px = x * size.width;
        final py = mid - y * (mid - 5) + off * size.height * 0.28;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: center ? 1 : 0.3)..style = PaintingStyle.stroke..strokeWidth = center ? 2.2 : 1.1);
    }
  }

  @override
  bool shouldRepaint(AnalogWavePainter old) => old.square != square || old.unison != unison;
}

/// フィルター特性（ローパスの概念図。カットオフとレゾナンスから描く）
class FilterCurvePainter extends CustomPainter {
  const FilterCurvePainter({required this.cutoffUnit, required this.resUnit, required this.color, required this.dim});

  /// 0〜1（対数スケール上の位置）
  final double cutoffUnit;

  /// 0〜1
  final double resUnit;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 4;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    final fc = 0.06 + cutoffUnit * 0.9;
    final path = Path();
    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final d = (x - fc) / 0.09;
      var y = 1 / (1 + math.exp(d * 3.2)) + resUnit * 0.55 * math.exp(-d * d * 2.2);
      y = math.min(1.25, y);
      final px = x * size.width;
      final py = base - y * (size.height - 10);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(FilterCurvePainter old) => old.cutoffUnit != cutoffUnit || old.resUnit != resUnit;
}

/// ADSR の形（各値は 0〜1 に正規化したもの。sustain のみそのまま高さ）
class AdsrPainter extends CustomPainter {
  const AdsrPainter({required this.a, required this.d, required this.s, required this.r, required this.color, required this.dim});

  final double a, d, s, r;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 4;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = dim.withValues(alpha: 0.35)..strokeWidth = 1);
    final ax = a.clamp(0.01, 0.35);
    final dx = d.clamp(0.01, 0.35);
    final rx = r.clamp(0.01, 0.35);
    final pts = <Offset>[
      Offset(0, base),
      Offset(ax * size.width, 4),
      Offset((ax + dx) * size.width, base - s * (size.height - 8)),
      Offset((1 - rx) * size.width, base - s * (size.height - 8)),
      Offset(size.width, base),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(AdsrPainter old) => old.a != a || old.d != d || old.s != s || old.r != r;
}
