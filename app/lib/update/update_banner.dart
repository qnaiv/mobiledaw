import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'updater.dart';

/// 新しい版があるときだけ出る帯。タップでダウンロードしてインストーラーを開く。
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

enum _Phase { idle, downloading, needsPermission, failed }

class _UpdateBannerState extends State<UpdateBanner> {
  final _updater = Updater();
  UpdateInfo? _info;
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _apkPath;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await _updater.check();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _update() async {
    final info = _info;
    if (info == null) return;
    try {
      var path = _apkPath;
      if (path == null) {
        setState(() {
          _phase = _Phase.downloading;
          _progress = 0;
        });
        path = await _updater.download(info, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
        _apkPath = path;
      }
      final result = await _updater.install(path);
      if (!mounted) return;
      setState(() => _phase = switch (result) {
            InstallResult.started => _Phase.idle,
            InstallResult.needsPermission => _Phase.needsPermission,
            InstallResult.failed => _Phase.failed,
          });
    } on Object {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _apkPath = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final firstLine = info.notes.split('\n').first;
    final message = switch (_phase) {
      _Phase.idle => firstLine.isEmpty ? '新しい版があります' : firstLine,
      _Phase.downloading => 'ダウンロード中… ${(_progress * 100).round()}%',
      _Phase.needsPermission => '「この提供元のアプリを許可」をオンにして戻り、もう一度押してください',
      _Phase.failed => 'うまくいきませんでした。もう一度押してください',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: DawColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('アップデート（build ${info.build}）', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: DawColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _phase == _Phase.downloading ? null : _update,
                  child: const Text('入れる'),
                ),
              ],
            ),
            if (_phase == _Phase.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              ),
          ],
        ),
      ),
    );
  }
}
