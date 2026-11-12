import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arrange/arrange_screen.dart';
import 'arrange/song_controller.dart';
import 'desktop/desktop_shell.dart';
import 'engine/mdaw_ffi.dart';
import 'kits/kit_store.dart';
import 'music/scale.dart';
import 'platform_paths.dart';
import 'project/library.dart';
import 'ui/scale_keyboard.dart';
import 'ui/theme.dart';
import 'update/updater.dart';

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
      home: const AppRoot(),
    );
  }
}

/// エンジンと曲を用意し、アレンジ画面を出す。アプリが裏に回ったら音を止めて保存する。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  MdawEngine? _engine;
  SongController? _song;
  String? _error;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _engine?.stopPlayback();
        _engine?.allNotesOff();
        _engine?.stop();
        _song?.saveNow();
      },
      onResume: () => _engine?.start(),
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final engine = MdawEngine.open();
      final filesDir = await appFilesDir();
      final library = ProjectLibrary(filesDir);
      final kits = KitStore(filesDir);
      engine.setKitsDir(kits.root.path);
      final song = SongController(engine, library: library, kits: kits, projectPath: library.initialPath())..open();
      final started = engine.start();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _song = song;
        if (started != MdawResult.ok) _error = '音声出力を開始できませんでした（$started）';
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'エンジンを読み込めませんでした: $e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _song?.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    final engine = _engine;
    if (song == null || engine == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: DawColors.danger)),
                ),
        ),
      );
    }
    void openSoundCheck() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SoundCheckScreen(engine: engine)),
        );
    // Windows では PC 用レイアウト（案A）。Android の画面遷移は従来どおり
    if (Platform.isWindows) {
      return DesktopShell(song: song, onOpenSoundCheck: openSoundCheck);
    }
    return ArrangeScreen(song: song, onOpenSoundCheck: openSoundCheck);
  }
}

/// M1：音が鳴ることと、触ってから鳴るまでの遅れを確かめる画面
class SoundCheckScreen extends StatefulWidget {
  const SoundCheckScreen({super.key, required this.engine});

  final MdawEngine engine;

  @override
  State<SoundCheckScreen> createState() => _SoundCheckScreenState();
}

class _SoundCheckScreenState extends State<SoundCheckScreen> {
  static const _scale = Scale(0, Scale.minorIntervals); // C minor

  EngineStatus? _status;
  Timer? _poll;

  int _octave = 4;
  double _brightness = 0.7;
  double _tail = 0.35;
  double _width = 0.3;

  MdawEngine get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _applyMacros();
    _status = _engine.status();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _status = _engine.status());
    });
  }

  /// マクロ（0〜1）→ シンセのパラメータ
  void _applyMacros() {
    final e = _engine;
    e.setParam(MdawParam.cutoffHz, 150 * math.pow(12000 / 150, _brightness).toDouble());
    e.setParam(MdawParam.resonance, 0.7 + _brightness * 0.8);
    e.setParam(MdawParam.releaseS, 0.02 * math.pow(2.5 / 0.02, _tail).toDouble());
    e.setParam(MdawParam.decayS, 0.08 + _tail * 0.8);
    e.setParam(MdawParam.detuneCents, _width * 25);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _engine.allNotesOff();
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
              const Row(
                children: [
                  BackButton(),
                  SizedBox(width: 4),
                  Text('音出しテスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Text('C minor · 鍵盤は下ほど強く鳴る · 指を滑らせると音が移る',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DawColors.muted)),
              const SizedBox(height: 16),
              _StatusPanel(status: _status, error: null),
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
                  onNoteOn: (note, velocity) => _engine.noteOn(note, velocity),
                  onNoteOff: (note) => _engine.noteOff(note),
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
      ('アプリの版', currentBuild == 0 ? '手元のビルド' : 'build $currentBuild'),
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
