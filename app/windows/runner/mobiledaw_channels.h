#ifndef RUNNER_MOBIDAW_CHANNELS_H_
#define RUNNER_MOBIDAW_CHANNELS_H_

#include <flutter/flutter_view_controller.h>

// Android の MainActivity と対になる MethodChannel を登録する。
//   mobiledaw/paths : filesDir
//   mobiledaw/share : exportsDir / share（共有シートの代わりに Explorer で表示）
//   mobiledaw/files : openFile / saveFile（Windows のファイルダイアログ）
// mobiledaw/updater は Windows では実装しない（Dart 側で Android 限定にガード済み）。
void RegisterMobiledawChannels(flutter::FlutterViewController* controller);

#endif  // RUNNER_MOBIDAW_CHANNELS_H_
