import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('mobiledaw/paths'); // MainActivity と揃える

/// アプリ専用の保存フォルダ（Android の filesDir）
Future<String> appFilesDir() async {
  final dir = await _channel.invokeMethod<String>('filesDir');
  if (dir == null) throw StateError('保存先を取得できませんでした');
  return dir;
}
