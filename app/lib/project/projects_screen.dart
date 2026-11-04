// 曲の一覧：開く・新しい曲・複製・名前を変える・削除。新しく保存した順に並ぶ。
import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../kits/kit_gate.dart';
import '../ui/theme.dart';
import 'library.dart';

/// 曲名を入れてもらう（空ならやめる）
Future<String?> askSongTitle(BuildContext context, {required String title, String initial = '', String ok = '決める'}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(hintText: '曲の名前'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(ok)),
      ],
    ),
  );
  controller.dispose();
  final t = name?.trim();
  return t == null || t.isEmpty ? null : t;
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.song});

  final SongController song;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  SongController get song => widget.song;
  ProjectLibrary get library => song.library;
  late List<ProjectEntry> _entries;

  @override
  void initState() {
    super.initState();
    song.saveNow(); // 開いている曲の名前・更新時刻を一覧に反映
    _entries = library.list();
  }

  void _reload() => setState(() => _entries = library.list());

  String _when(DateTime t) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(t.hour)}:${two(t.minute)}';
    if (now.year == t.year && now.month == t.month && now.day == t.day) return '今日 $hm';
    return '${t.year}/${two(t.month)}/${two(t.day)} $hm';
  }

  /// 開く。使っているキットが足りなければ、ダウンロードするまで開かない
  Future<void> _open(ProjectEntry e) async {
    if (e.id != song.projectId && !await ensureKits(context, song, kitsInProjectFile(e.path))) return;
    if (!mounted) return;
    song.openProject(e.id);
    Navigator.pop(context);
  }

  Future<void> _new() async {
    final title = await askSongTitle(context, title: '新しい曲', initial: '無題の曲', ok: '作る');
    if (title == null || !mounted) return;
    song.newSong(title: title);
    Navigator.pop(context);
  }

  Future<void> _rename(ProjectEntry e) async {
    final title = await askSongTitle(context, title: '名前を変える', initial: e.title);
    if (title == null) return;
    if (e.id == song.projectId) {
      song.renameSong(title);
      song.saveNow();
    } else {
      library.rename(e.id, title);
    }
    _reload();
  }

  void _duplicate(ProjectEntry e) {
    if (e.id == song.projectId) song.saveNow();
    library.duplicate(e.id);
    _reload();
  }

  Future<void> _delete(ProjectEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${e.title}」を削除しますか？'),
        content: const Text('削除した曲は元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DawColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final wasOpen = e.id == song.projectId;
    library.delete(e.id);
    if (wasOpen) {
      // 開いていた曲を消したら、残っている一番新しい曲か新しい曲を開く
      final rest = [for (final r in library.list()) if (missingKits(song.kits, kitsInProjectFile(r.path)).isEmpty) r];
      if (rest.isEmpty) {
        song.newSong();
      } else {
        song.openProject(rest.first.id);
      }
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final current = song.projectId;
    return Scaffold(
      appBar: AppBar(title: const Text('曲の一覧')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('新しい曲'),
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('まだ曲がありません', style: TextStyle(color: DawColors.muted)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: _entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final isOpen = e.id == current;
                return Material(
                  color: DawColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isOpen ? DawColors.accent : DawColors.line),
                    ),
                    leading: Icon(isOpen ? Icons.music_note : Icons.music_note_outlined,
                        color: isOpen ? DawColors.accent : DawColors.muted),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(isOpen ? '開いている曲 · ${_when(e.updated)}' : _when(e.updated),
                        style: const TextStyle(fontSize: 12, color: DawColors.muted)),
                    onTap: () => _open(e),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            _rename(e);
                          case 'duplicate':
                            _duplicate(e);
                          case 'delete':
                            _delete(e);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('名前を変える')),
                        PopupMenuItem(value: 'duplicate', child: Text('複製')),
                        PopupMenuItem(value: 'delete', child: Text('削除')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
