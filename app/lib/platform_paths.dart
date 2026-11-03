import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('mobiledaw/paths'); // MainActivity と揃える

/// アプリ専用の保存フォルダ（Android の filesDir）
Future<String> appFilesDir() async {
  final dir = await _channel.invokeMethod<String>('filesDir');
  if (dir == null) throw StateError('保存先を取得できませんでした');
  return dir;
}

/// いま開いている曲の保存先。設計書の保存フォルダ（<名前>.qdaw/project.json）に合わせる
String projectFilePath(String filesDir) => '$filesDir/projects/untitled-01.qdaw/project.json';
