// Windows 用の PC レイアウト（案A「3ペイン統合」）。main.dart が
// Platform.isWindows のときだけこちらを使う。Android の画面は一切変えない。
//
// 上：ツールバー（再生/停止・テンポ・キー・スナップ表示・Undo/Redo・ビュー切替）
// 左：トラック一覧＋簡易ミキサー（track_sidebar.dart）
// 中央：ビュー切替。アレンジは既存の ArrangeScreen をそのまま置く
//      （Scaffold を含む画面単位の作りで、本体だけの切り出しは大規模になるため。
//       HANDOFF 参照）。ピアノロールは選択中クリップの PianoRollScreen を、
//       音色はトラックを選んで既存の音色シートを開く形。
// 右：選択中クリップの数値編集＋プロジェクト情報（inspector_panel.dart）
//
// ショートカット：Space = 再生/停止、Ctrl+Z = 元に戻す、
// Ctrl+Shift+Z / Ctrl+Y = やり直し、Ctrl+S = 保存。
// ピアノロール表示中はそちらのキー処理が優先されるよう、テキスト入力中と
// 中央がピアノロールのときは Space を奪わない。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arrange/arrange_screen.dart';
import '../arrange/song_controller.dart';
import '../music/scale.dart';
import '../piano_roll/piano_roll_screen.dart';
import '../sound/sound_sheet.dart';
import '../ui/theme.dart';
import 'inspector_panel.dart';
import 'track_sidebar.dart';

enum DesktopView { arrange, roll, sound }

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.song, required this.onOpenSoundCheck});

  final SongController song;
  final VoidCallback onOpenSoundCheck;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopView _view = DesktopView.arrange;
  bool _playing = false;
  Timer? _poll;

  SongController get song => widget.song;

  @override
  void initState() {
    super.initState();
    // 再生状態はエンジンからポーリング（アレンジ画面の Ticker と同じ読み方）
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final p = song.engine.isPlaying;
      if (mounted && p != _playing) setState(() => _playing = p);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final control = HardwareKeyboard.instance.isControlPressed;
    if (control && key == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        song.redo();
      } else {
        song.undo();
      }
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyY) {
      song.redo();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyS) {
      song.saveNow(force: true);
      return KeyEventResult.handled;
    }
    // Space はテキスト入力中とピアノロール表示中には渡さない（そちらの操作を優先）
    if (key == LogicalKeyboardKey.space && _view == DesktopView.arrange) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context?.widget is EditableText) return KeyEventResult.ignored;
      song.togglePlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: song,
          builder: (context, _) {
            final p = song.project;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(p.title),
                const Divider(height: 1, color: DawColors.line),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 232, child: TrackSidebar(song: song)),
                      const VerticalDivider(width: 1, color: DawColors.line),
                      Expanded(child: _center()),
                      const VerticalDivider(width: 1, color: DawColors.line),
                      SizedBox(width: 264, child: InspectorPanel(song: song)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar(String title) {
    final p = song.project;
    return Container(
      color: DawColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: _playing ? '停止 (Space)' : '再生 (Space)',
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            onPressed: () => song.togglePlay(),
          ),
          IconButton(
            tooltip: '先頭へ',
            icon: const Icon(Icons.skip_previous),
            onPressed: () => song.rewind(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
          _chip('テンポ', '${p.tempo.toStringAsFixed(p.tempo % 1 == 0 ? 0 : 1)}'),
          _chip('キー', '${noteName(p.keyRoot)} ${p.scale}'),
          _chip('拍子', '${p.timeSigNumerator}/${p.timeSigDenominator}'),
          _chip('長さ', '${p.lengthBars} 小節'),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '元に戻す (Ctrl+Z)',
            icon: const Icon(Icons.undo),
            onPressed: song.canUndo ? () => song.undo() : null,
          ),
          IconButton(
            tooltip: 'やり直し (Ctrl+Shift+Z)',
            icon: const Icon(Icons.redo),
            onPressed: song.canRedo ? () => song.redo() : null,
          ),
          IconButton(
            tooltip: '保存 (Ctrl+S)',
            icon: const Icon(Icons.save_outlined),
            onPressed: () => song.saveNow(force: true),
          ),
          const SizedBox(width: 8),
          SegmentedButton<DesktopView>(
            segments: const [
              ButtonSegment(value: DesktopView.arrange, label: Text('アレンジ')),
              ButtonSegment(value: DesktopView.roll, label: Text('ピアノロール')),
              ButtonSegment(value: DesktopView.sound, label: Text('音色')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$label $value', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _center() {
    switch (_view) {
      case DesktopView.arrange:
        return ArrangeScreen(key: const ValueKey('desktop-arrange'), song: song, onOpenSoundCheck: widget.onOpenSoundCheck);
      case DesktopView.roll:
        final sel = song.selected;
        if (sel == null) {
          return const Center(
            child: Text('クリップが選ばれていません。アレンジでクリップを選んでください',
                style: TextStyle(color: DawColors.muted)),
          );
        }
        return PianoRollScreen(key: ValueKey('desktop-roll-${sel.id}'), song: song, placementId: sel.id);
      case DesktopView.sound:
        return _soundPicker();
    }
  }

  /// 音色ビュー：トラックを選ぶと既存の音色シートを開く（Phase 1 の形）
  Widget _soundPicker() {
    final tracks = song.project.tracks;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('音色を編集するトラック', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('選ぶとスマホ版と同じ音色シートが開きます', style: TextStyle(color: DawColors.muted, fontSize: 12)),
        const SizedBox(height: 12),
        for (final t in tracks)
          ListTile(
            leading: CircleAvatar(backgroundColor: Color(t.color), radius: 10),
            title: Text(t.name),
            subtitle: Text(t.isKit ? 'キット: ${t.kitId}' : (t.isSampler ? 'サンプラー' : 'シンセ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showSoundSheet(context, song, t.id),
          ),
      ],
    );
  }
}
