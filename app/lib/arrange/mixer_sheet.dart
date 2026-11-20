// ミキサー：チャンネルストリップの横並び（パン・センド・フェーダー・M/S・レベルメーター）。
// トラック名をタップすると下から出る。マスターは右端に固定。
// レベルメーターは 50ms ごとにコアのピーク（読むと 0 に戻る保持値）を読み、
// こちらの側で減衰させて表示する。
import 'dart:async';

import 'package:flutter/material.dart';

import '../model/project.dart';
import '../sound/sound_params.dart';
import '../ui/theme.dart';
import 'channel_strip.dart';
import 'song_controller.dart';

export 'channel_strip.dart' show gainLabel, panLabel;

Future<void> showMixerSheet(BuildContext context, SongController song, {int? focusTrackId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _MixerSheet(song: song, focusTrackId: focusTrackId),
  );
}

class _MixerSheet extends StatefulWidget {
  const _MixerSheet({required this.song, this.focusTrackId});

  final SongController song;
  final int? focusTrackId;

  @override
  State<_MixerSheet> createState() => _MixerSheetState();
}

class _MixerSheetState extends State<_MixerSheet> {
  int? _selectedTrackId;
  final Map<int, ValueNotifier<double>> _peaks = {};
  final ValueNotifier<double> _masterPeak = ValueNotifier<double>(0);
  Timer? _peakTimer;

  SongController get song => widget.song;

  @override
  void initState() {
    super.initState();
    _selectedTrackId = widget.focusTrackId;
    _peakTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _pollPeaks());
  }

  @override
  void dispose() {
    _peakTimer?.cancel();
    for (final n in _peaks.values) {
      n.dispose();
    }
    _masterPeak.dispose();
    super.dispose();
  }

  ValueNotifier<double> _peakOf(int trackId) => _peaks.putIfAbsent(trackId, () => ValueNotifier<double>(0));

  /// コアの保持ピークを読み、表示値を「読み値か、減衰した前回値の大きい方」にする
  void _pollPeaks() {
    if (!mounted) return;
    for (final t in song.project.tracks) {
      final n = _peakOf(t.id);
      n.value = nextMeterLevel(song.trackPeak(t.id), n.value);
    }
    _masterPeak.value = nextMeterLevel(song.masterPeak(), _masterPeak.value);
  }

  Future<void> _rename(BuildContext context, TrackData track) async {
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
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListenableBuilder(
          listenable: song,
          builder: (context, _) {
            final tracks = song.project.tracks;
            final anySolo = tracks.any((t) => t.mixer.solo);
            final revParam = allSoundParams.firstWhere((e) => e.key == 'sendReverb');
            final dlyParam = allSoundParams.firstWhere((e) => e.key == 'sendDelay');
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
                  child: Text('再生しながら動かせます。M＝消音、S＝そのトラックだけ鳴らす。フェーダーはダブルタップで 0 dB、ノブはダブルタップで戻ります',
                      style: TextStyle(fontSize: 11, color: DawColors.muted)),
                ),
                const SizedBox(height: 8),
                // ストリップ列（横スクロール）＋マスター固定。下揃えでフェーダーの位置を合わせる
                SizedBox(
                  height: 392,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final t in tracks)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _stripFor(t, anySolo, revParam, dlyParam),
                                ),
                            ],
                          ),
                        ),
                      ),
                      MasterStrip(
                        gain: song.project.master.gain,
                        peak: _masterPeak,
                        onGainChanged: (v) => song.setMaster(gain: v),
                        onGainStart: song.beginGesture,
                        onGainEnd: (_) => song.endGesture(),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      _MasterCard(song: song),
                      _AuxCard(song: song),
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

  Widget _stripFor(TrackData t, bool anySolo, SoundParam revParam, SoundParam dlyParam) {
    final m = t.mixer;
    return ChannelStrip(
      name: t.name,
      color: Color(t.color),
      selected: t.id == _selectedTrackId,
      dimmed: m.mute || (anySolo && !m.solo),
      gain: m.gain,
      pan: m.pan,
      mute: m.mute,
      solo: m.solo,
      sendReverbParam: revParam,
      sendReverb: revParam.valueOf(t),
      sendDelayParam: dlyParam,
      sendDelay: dlyParam.valueOf(t),
      peak: _peakOf(t.id),
      onSelect: () => setState(() => _selectedTrackId = t.id),
      onRename: () => _rename(context, t),
      onGainChanged: (v) => song.setMixer(t.id, gain: v),
      onGainStart: song.beginGesture,
      onGainEnd: (_) => song.endGesture(),
      onPanChanged: (v) => song.setMixer(t.id, pan: v.abs() < 0.04 ? 0 : v),
      onSendChanged: (p, v) => song.setSound(t.id, p.id, v),
      onKnobStart: song.beginGesture,
      onKnobEnd: (_) => song.endGesture(),
      onMuteToggle: () => song.setMixer(t.id, mute: !m.mute),
      onSoloToggle: () => song.setMixer(t.id, solo: !m.solo),
    );
  }
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({required this.song});
  final SongController song;

  @override
  Widget build(BuildContext context) {
    final m = song.project.master;
    return _BusCard(
      title: 'マスター仕上げ（音量は右端のストリップで）',
      children: [
        _SliderLine(
          icon: Icons.compress,
          value: m.glue,
          min: 0,
          max: 1,
          label: '${(m.glue * 100).round()}%',
          color: DawColors.accent,
          resetTo: 1,
          song: song,
          onChanged: (v) => song.setMaster(glue: v),
        ),
        _SliderLine(
          icon: Icons.horizontal_rule,
          value: m.thresholdDb,
          min: -30,
          max: 0,
          label: '${m.thresholdDb.toStringAsFixed(0)} dB',
          color: DawColors.accent,
          resetTo: -12,
          song: song,
          onChanged: (v) => song.setMaster(thresholdDb: v),
        ),
        _SliderLine(
          icon: Icons.blur_on,
          value: m.softClip,
          min: 0,
          max: 1,
          label: '${(m.softClip * 100).round()}%',
          color: DawColors.accent,
          resetTo: 1,
          song: song,
          onChanged: (v) => song.setMaster(softClip: v),
        ),
        _SliderLine(
          icon: Icons.vertical_align_top,
          value: m.ceiling,
          min: 0.5,
          max: 1,
          label: gainLabel(m.ceiling),
          color: DawColors.accent,
          resetTo: 0.944,
          song: song,
          onChanged: (v) => song.setMaster(ceiling: v),
        ),
      ],
    );
  }
}

class _AuxCard extends StatelessWidget {
  const _AuxCard({required this.song});
  final SongController song;

  @override
  Widget build(BuildContext context) {
    final a = song.project.aux;
    return _BusCard(
      title: 'センド（リバーブ / ディレイ）',
      children: [
        _SliderLine(
          icon: Icons.waves,
          value: a.reverbReturn,
          min: 0,
          max: 1.5,
          label: '${(a.reverbReturn * 100).round()}%',
          color: DawColors.accent,
          resetTo: 1,
          song: song,
          onChanged: (v) => song.setAux(reverbReturn: v),
        ),
        _SliderLine(
          icon: Icons.open_in_full,
          value: a.reverbSize,
          min: 0,
          max: 1,
          label: '${(a.reverbSize * 100).round()}%',
          color: DawColors.accent,
          resetTo: 0.65,
          song: song,
          onChanged: (v) => song.setAux(reverbSize: v),
        ),
        _SliderLine(
          icon: Icons.repeat,
          value: a.delayReturn,
          min: 0,
          max: 1.5,
          label: '${(a.delayReturn * 100).round()}%',
          color: DawColors.accent,
          resetTo: 0.8,
          song: song,
          onChanged: (v) => song.setAux(delayReturn: v),
        ),
        _SliderLine(
          icon: Icons.loop,
          value: a.delayFeedback,
          min: 0,
          max: 0.9,
          label: '${(a.delayFeedback * 100).round()}%',
          color: DawColors.accent,
          resetTo: 0.35,
          song: song,
          onChanged: (v) => song.setAux(delayFeedback: v),
        ),
      ],
    );
  }
}

class _BusCard extends StatelessWidget {
  const _BusCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
      decoration: BoxDecoration(
        color: DawColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DawColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ...children,
        ],
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
                onChangeStart: (_) => song.beginGesture(),
                onChanged: onChanged,
                onChangeEnd: (_) => song.endGesture(),
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
