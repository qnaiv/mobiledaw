import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine/mdaw_ffi.dart';
import 'music/scale.dart';
import 'ui/scale_keyboard.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  runApp(const MobileDawApp());
}

class MobileDawApp extends StatelessWidget {
  const MobileDawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mobiledaw',
      debugShowCheckedModeBanner: false,
      theme: buildDawTheme(),
      home: const SoundCheckScreen(),
    );
  }
}

/// M1：音が鳴ることと、触ってから鳴るまでの遅れを確かめる画面
class SoundCheckScreen extends StatefulWidget {
  const SoundCheckScreen({super.key});

  @override
  State<SoundCheckScreen> createState() => _SoundCheckScreenState();
}

class _SoundCheckScreenState extends State<SoundCheckScreen> {
  static const _scale = Scale(0, Scale.minorIntervals); // C minor

  MdawEngine? _engine;
  String? _error;
  EngineStatus? _status;
  Timer? _poll;
  late final AppLifecycleListener _lifecycle;

  int _octave = 4;
  double _brightness = 0.7;
  double _tail = 0.35;
  double _width = 0.3;

  @override
  void initState() {
    super.initState();
    try {
      _engine = MdawEngine.open();
      _applyMacros();
      _error = _startAudio();
    } catch (e) {
      _error = 'エンジンを読み込めませんでした: $e';
    }
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _engine?.allNotesOff();
        _engine?.stop();
      },
      onResume: () => setState(() => _error = _startAudio()),
    );
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final engine = _engine;
      if (engine != null && mounted) setState(() => _status = engine.status());
    });
  }

  /// 音声出力を開始し、失敗したら表示用のメッセージを返す
  String? _startAudio() {
    final engine = _engine;
    if (engine == null) return _error;
    return switch (engine.start()) {
      MdawResult.ok => null,
      MdawResult.openFailed => '音声出力を開けませんでした',
      MdawResult.startFailed => '音声出力を開始できませんでした',
      final other => '音声出力が使えません（$other）',
    };
  }

  /// マクロ（0〜1）→ シンセのパラメータ
  void _applyMacros() {
    final e = _engine;
    if (e == null) return;
    e.setParam(MdawParam.cutoffHz, 150 * math.pow(12000 / 150, _brightness).toDouble());
    e.setParam(MdawParam.resonance, 0.7 + _brightness * 0.8);
    e.setParam(MdawParam.releaseS, 0.02 * math.pow(2.5 / 0.02, _tail).toDouble());
    e.setParam(MdawParam.decayS, 0.08 + _tail * 0.8);
    e.setParam(MdawParam.detuneCents, _width * 25);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _scale.notesFrom(_octave);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('音出しテスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('C minor · 鍵盤は下ほど強く鳴る · 指を滑らせると音が移る',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DawColors.muted)),
              const SizedBox(height: 16),
              _StatusPanel(status: _status, error: _error),
              const SizedBox(height: 20),
              _MacroSlider(
                label: '明るさ',
                value: _brightness,
                onChanged: (v) {
                  setState(() => _brightness = v);
                  _applyMacros();
                },
              ),
              _MacroSlider(
                label: '余韻',
                value: _tail,
                onChanged: (v) {
                  setState(() => _tail = v);
                  _applyMacros();
                },
              ),
              _MacroSlider(
                label: '広がり',
                value: _width,
                onChanged: (v) {
                  setState(() => _width = v);
                  _applyMacros();
                },
              ),
              const Spacer(),
              Row(
                children: [
                  Text('オクターブ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DawColors.muted)),
                  const SizedBox(width: 8),
                  Text(noteName(notes.first, withOctave: true), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _RoundButton(
                    icon: Icons.remove,
                    label: 'オクターブを下げる',
                    onPressed: _octave > 1 ? () => setState(() => _octave--) : null,
                  ),
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.add,
                    label: 'オクターブを上げる',
                    onPressed: _octave < 6 ? () => setState(() => _octave++) : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 180,
                child: ScaleKeyboard(
                  notes: notes,
                  rootPitchClass: _scale.root,
                  onNoteOn: (note, velocity) => _engine?.noteOn(note, velocity),
                  onNoteOff: (note) => _engine?.noteOff(note),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status, required this.error});

  final EngineStatus? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = status;
    String fmt(double ms) => ms < 0 ? '不明' : '${ms.toStringAsFixed(1)} ms';
    final rows = <(String, String)>[
      ('サンプルレート', s == null || s.sampleRate == 0 ? '—' : '${s.sampleRate} Hz'),
      ('バースト／バッファ', s == null ? '—' : '${s.framesPerBurst} / ${s.bufferSizeFrames} frames（${fmt(s.bufferMs)}）'),
      ('出力遅延（推定）', s == null ? '—' : fmt(s.outputLatencyMs)),
      ('音切れ回数', s == null || s.xruns < 0 ? '—' : '${s.xruns}'),
      ('鳴っている声', s == null ? '—' : '${s.activeVoices} / 8'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!, style: const TextStyle(color: DawColors.danger, fontWeight: FontWeight.w700)),
            ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(label, style: const TextStyle(color: DawColors.muted, fontSize: 13)),
                  const Spacer(),
                  Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MacroSlider extends StatelessWidget {
  const _MacroSlider({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 14))),
          Expanded(child: Slider(value: value, onChanged: onChanged)),
          SizedBox(
            width: 32,
            child: Text('${(value * 100).round()}',
                textAlign: TextAlign.right, style: const TextStyle(color: DawColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: DawColors.line),
      ),
    );
  }
}
