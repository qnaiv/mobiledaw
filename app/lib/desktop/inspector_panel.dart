// PC レイアウト案A の右インスペクタ。
// 選択中クリップの開始小節・長さを数値入力で編集する（SongController の
// movePlacementTo / resizeClip を使う。ぶつかる配置は false が返るので
// その旨を出す）。下段はプロジェクト情報（テンポの数値編集つき）と
// ショートカット一覧。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arrange/song_controller.dart';
import '../music/scale.dart';
import '../ui/theme.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.song});

  final SongController song;

  @override
  Widget build(BuildContext context) {
    final p = song.project;
    final sel = song.selected;
    return Container(
      color: DawColors.panel,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('選択中クリップ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (sel == null)
            const Text('クリップが選ばれていません', style: TextStyle(color: DawColors.muted, fontSize: 12))
          else ...[
            Text(
              '${p.track(sel.trackId)?.name ?? ''} ／ クリップ ${sel.clipId}',
              style: const TextStyle(fontSize: 12, color: DawColors.muted),
            ),
            const SizedBox(height: 10),
            _IntField(
              label: '開始（小節）',
              initial: sel.startBar + 1, // 画面表示は1始まり、モデルは0始まり
              onSubmit: (v) {
                if (!song.movePlacementTo(sel.id, v - 1)) {
                  _showError(context, 'そこには置けません（他のクリップと重なります）');
                }
              },
            ),
            const SizedBox(height: 8),
            _IntField(
              label: '長さ（小節）',
              initial: sel.lengthBars,
              onSubmit: (v) {
                if (v < 1 || !song.resizeClip(sel.clipId, v)) {
                  _showError(context, 'その長さにはできません');
                }
              },
            ),
            const SizedBox(height: 6),
            const Text('長さは同じパターンの複製すべてに効きます', style: TextStyle(color: DawColors.muted, fontSize: 11)),
          ],
          const Divider(height: 28, color: DawColors.line),
          const Text('プロジェクト', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _row('キー', '${noteName(p.keyRoot)} ${p.scale}'),
          _row('拍子', '${p.timeSigNumerator}/${p.timeSigDenominator}'),
          _row('長さ', '${p.lengthBars} 小節'),
          const SizedBox(height: 8),
          _TempoField(song: song),
          const Divider(height: 28, color: DawColors.line),
          const Text('ショートカット', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _row('Space', '再生 / 停止'),
          _row('Ctrl+Z', '元に戻す'),
          _row('Ctrl+Shift+Z / Ctrl+Y', 'やり直し'),
          _row('Ctrl+S', '保存'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: DawColors.muted, fontSize: 12))),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _showError(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

/// 数値入力して Enter で確定する欄。外部の値が変わったら追従する
class _IntField extends StatefulWidget {
  const _IntField({required this.label, required this.initial, required this.onSubmit});

  final String label;
  final int initial;
  final void Function(int value) onSubmit;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.initial}');
  bool _focused = false;

  @override
  void didUpdateWidget(_IntField old) {
    super.didUpdateWidget(old);
    if (!_focused && widget.initial != old.initial) {
      _controller.text = '${widget.initial}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(widget.label, style: const TextStyle(color: DawColors.muted, fontSize: 12))),
        SizedBox(
          width: 72,
          child: Focus(
            onFocusChange: (f) => _focused = f,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
              onSubmitted: (text) {
                final v = int.tryParse(text);
                if (v != null) widget.onSubmit(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TempoField extends StatefulWidget {
  const _TempoField({required this.song});

  final SongController song;

  @override
  State<_TempoField> createState() => _TempoFieldState();
}

class _TempoFieldState extends State<_TempoField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.song.project.tempo.toStringAsFixed(0));
  bool _focused = false;

  @override
  void didUpdateWidget(_TempoField old) {
    super.didUpdateWidget(old);
    if (!_focused) {
      final t = widget.song.project.tempo.toStringAsFixed(0);
      if (_controller.text != t) _controller.text = t;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text('テンポ (BPM)', style: TextStyle(color: DawColors.muted, fontSize: 12))),
        SizedBox(
          width: 72,
          child: Focus(
            onFocusChange: (f) => _focused = f,
            child: TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
              onSubmitted: (text) {
                final v = double.tryParse(text);
                if (v != null && v >= 20 && v <= 300) widget.song.setTempo(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
