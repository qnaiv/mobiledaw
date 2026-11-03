// ミキサー：トラックごとの音量・パン・ミュート・ソロ。
// トラック名をタップすると下から出る。全トラックが並ぶので、聴きながらバランスを取れる。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/project.dart';
import '../ui/theme.dart';
import 'song_controller.dart';

Future<void> showMixerSheet(BuildContext context, SongController song, {int? focusTrackId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _MixerSheet(song: song, focusTrackId: focusTrackId),
  );
}

/// 音量（倍率）を dB の文字に
String gainLabel(double gain) {
  if (gain <= 0.0005) return '-∞ dB';
  final db = 20 * math.log(gain) / math.ln10;
  return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
}

String panLabel(double pan) {
  final v = (pan * 100).round();
  if (v == 0) return 'C';
  return v < 0 ? 'L${-v}' : 'R$v';
}

class _MixerSheet extends StatelessWidget {
  const _MixerSheet({required this.song, this.focusTrackId});

  final SongController song;
  final int? focusTrackId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListenableBuilder(
          listenable: song,
          builder: (context, _) {
            final tracks = song.project.tracks;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                  child: Row(
                    children: [
                      const Text('ミキサー', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        tooltip: '元に戻す',
                        onPressed: song.canUndo ? song.undo : null,
                        icon: const Icon(Icons.undo),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('再生しながら動かせます。M＝消音、S＝そのトラックだけ鳴らす',
                      style: TextStyle(fontSize: 11, color: DawColors.muted)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    children: [
                      for (final t in tracks)
                        _MixerRow(song: song, track: t, focused: t.id == focusTrackId),
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
}

class _MixerRow extends StatelessWidget {
  const _MixerRow({required this.song, required this.track, required this.focused});

  final SongController song;
  final TrackData track;
  final bool focused;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: track.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('トラックの名前'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('決める')),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) song.renameTrack(track.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final m = track.mixer;
    final color = Color(track.color);
    final anySolo = song.project.tracks.any((t) => t.mixer.solo);
    final silent = m.mute || (anySolo && !m.solo);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: DawColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: focused ? color : DawColors.line, width: focused ? 1.5 : 1),
      ),
      child: Opacity(
        opacity: silent ? 0.5 : 1,
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _rename(context),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 14, color: DawColors.muted),
                      ],
                    ),
                  ),
                ),
                _Toggle(
                  label: 'M',
                  on: m.mute,
                  onColor: DawColors.danger,
                  onTap: () => song.setMixer(track.id, mute: !m.mute),
                ),
                const SizedBox(width: 6),
                _Toggle(
                  label: 'S',
                  on: m.solo,
                  onColor: DawColors.accent,
                  onTap: () => song.setMixer(track.id, solo: !m.solo),
                ),
              ],
            ),
            _SliderLine(
              icon: Icons.volume_up,
              value: m.gain,
              min: 0,
              max: 2,
              label: gainLabel(m.gain),
              color: color,
              // 右の数字をダブルタップで 0 dB に戻す
              resetTo: 1,
              song: song,
              onChanged: (v) => song.setMixer(track.id, gain: v),
            ),
            _SliderLine(
              icon: Icons.swap_horiz,
              value: m.pan,
              min: -1,
              max: 1,
              label: panLabel(m.pan),
              color: color,
              resetTo: 0,
              song: song,
              onChanged: (v) => song.setMixer(track.id, pan: (v.abs() < 0.04) ? 0 : v),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderLine extends StatelessWidget {
  const _SliderLine({
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.color,
    required this.resetTo,
    required this.song,
    required this.onChanged,
  });

  final IconData icon;
  final double value, min, max, resetTo;
  final String label;
  final Color color;
  final SongController song;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: DawColors.muted),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                onChangeStart: (_) => song.beginMixerGesture(),
                onChanged: onChanged,
                onChangeEnd: (_) => song.endMixerGesture(),
              ),
            ),
          ),
          GestureDetector(
            onDoubleTap: () => onChanged(resetTo),
            child: SizedBox(
              width: 64,
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.on, required this.onColor, required this.onTap});

  final String label;
  final bool on;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? onColor : DawColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? onColor : DawColors.line),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, color: on ? DawColors.background : DawColors.muted)),
      ),
    );
  }
}
