// 音色シート：トラック名タップで出る。プリセットを選ぶ → 大きいつまみで整える → 必要なら「詳しく」。
// つまみは再生しながら動かせて、離すまでが1回の Undo。
import 'package:flutter/material.dart';

import '../arrange/mixer_sheet.dart';
import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../ui/theme.dart';
import 'sound_params.dart';

Future<void> showSoundSheet(BuildContext context, SongController song, int trackId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _SoundSheet(song: song, trackId: trackId),
  );
}

class _SoundSheet extends StatelessWidget {
  const _SoundSheet({required this.song, required this.trackId});

  final SongController song;
  final int trackId;

  void _audition() {
    song.previewTrack(trackId);
    song.auditionChord(const [60, 63, 67, 70]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListenableBuilder(
          listenable: song,
          builder: (context, _) {
            final track = song.project.track(trackId);
            if (track == null) return const SizedBox(height: 120, child: Center(child: Text('トラックがありません')));
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: Color(track.color), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${track.name} の音色',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(tooltip: '試聴', onPressed: _audition, icon: const Icon(Icons.play_circle_outline)),
                    IconButton(
                      tooltip: 'ミキサー',
                      onPressed: () => showMixerSheet(context, song, focusTrackId: trackId),
                      icon: const Icon(Icons.tune),
                    ),
                    IconButton(
                      tooltip: '元に戻す',
                      onPressed: song.canUndo ? song.undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const _Caption('プリセット'),
                _PresetRow(song: song, trackId: trackId),
                const SizedBox(height: 12),
                const _Caption('大きいつまみ'),
                for (final m in soundMacros) _MacroSlider(song: song, track: track, macro: m),
                const SizedBox(height: 8),
                _DetailSection(title: '詳しく：音の素・フィルター・エンベロープ', song: song, track: track, params: synthParams),
                _DetailSection(title: '詳しく：エフェクト', song: song, track: track, params: fxParams),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, color: DawColors.muted)),
      );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.song, required this.trackId});

  final SongController song;
  final int trackId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: soundPresets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final p = soundPresets[i];
          return ActionChip(
            label: Text(p.name),
            tooltip: p.category,
            onPressed: () {
              song.setSounds(trackId, p.allValues);
              song.previewTrack(trackId);
              song.auditionChord(p.category == 'ドラム' ? const [48] : const [60, 63, 67, 70]);
            },
          );
        },
      ),
    );
  }
}

class _MacroSlider extends StatelessWidget {
  const _MacroSlider({required this.song, required this.track, required this.macro});

  final SongController song;
  final TrackData track;
  final SoundMacro macro;

  @override
  Widget build(BuildContext context) {
    final color = Color(track.color);
    final value = macro.read(track).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(macro.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(macro.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: DawColors.muted)),
              ],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value,
                onChangeStart: (_) => song.beginGesture(),
                onChanged: (u) => song.setSounds(track.id, macro.write(u)),
                onChangeEnd: (_) => song.endGesture(),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${(value * 100).round()}',
                textAlign: TextAlign.right, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.song, required this.track, required this.params});

  final String title;
  final SongController song;
  final TrackData track;
  final List<SoundParam> params;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        children: [for (final p in params) _ParamRow(song: song, track: track, param: p)],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({required this.song, required this.track, required this.param});

  final SongController song;
  final TrackData track;
  final SoundParam param;

  @override
  Widget build(BuildContext context) {
    final v = param.valueOf(track);
    if (param.scale == ParamScale.toggle) {
      final on = v >= 0.5;
      final labels = param.id == MdawParam.wave ? ('のこぎり', '矩形') : ('オフ', 'オン');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(param.label, style: const TextStyle(fontSize: 13))),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(labels.$1)),
                ButtonSegment(value: true, label: Text(labels.$2)),
              ],
              selected: {on},
              onSelectionChanged: (s) => song.setSound(track.id, param.id, s.first ? 1 : 0),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(param.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: param.toUnit(v),
              onChangeStart: (_) => song.beginGesture(),
              onChanged: (u) => song.setSound(track.id, param.id, param.fromUnit(u)),
              onChangeEnd: (_) => song.endGesture(),
            ),
          ),
          GestureDetector(
            // ダブルタップで既定値に戻す
            onDoubleTap: () => song.setSound(track.id, param.id, param.def),
            child: SizedBox(
              width: 70,
              child: Text(param.format(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      ),
    );
  }
}
