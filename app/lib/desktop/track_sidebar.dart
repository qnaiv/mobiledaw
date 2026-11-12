// PC レイアウト案A の左サイドバー：トラック一覧＋各トラックの簡易ミキサー。
// 音量スライダーはスマホ版のミキサーと同じく beginGesture/endGesture で
// 1ジェスチャー＝1 Undo にまとめる（song_controller の流儀）。
import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../ui/theme.dart';

class TrackSidebar extends StatelessWidget {
  const TrackSidebar({super.key, required this.song});

  final SongController song;

  @override
  Widget build(BuildContext context) {
    final p = song.project;
    return Container(
      color: DawColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                const Text('トラック', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'トラックを追加',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: song.canAddTrack ? () => song.addTrack() : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final t in p.tracks)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(t.color), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                            _miniToggle('M', t.mixer.mute, () => song.setMixer(t.id, mute: !t.mixer.mute)),
                            _miniToggle('S', t.mixer.solo, () => song.setMixer(t.id, solo: !t.mixer.solo)),
                          ],
                        ),
                        Row(
                          children: [
                            const Icon(Icons.volume_up, size: 14, color: DawColors.muted),
                            Expanded(
                              child: Slider(
                                value: t.mixer.gain.clamp(0, 2),
                                min: 0,
                                max: 2,
                                onChangeStart: (_) => song.beginGesture(),
                                onChanged: (v) => song.setMixer(t.id, gain: v),
                                onChangeEnd: (_) => song.endGesture(),
                              ),
                            ),
                            SizedBox(
                              width: 30,
                              child: Text('${(t.mixer.gain * 100).round()}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: DawColors.muted, fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: DawColors.line),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text('詳しいミキサー（EQ・コンプ・センド）はアレンジ画面のミキサーボタンから開けます',
                style: TextStyle(color: DawColors.muted, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _miniToggle(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: active ? DawColors.accent : Colors.transparent,
            border: Border.all(color: DawColors.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.black : DawColors.muted)),
        ),
      ),
    );
  }
}
