// メニュー「デモ曲」で入る曲。同梱のプロジェクトファイル（assets/demos/）を新しい曲として一覧に入れる。
// ・kawaii フューチャーベース：150 BPM・F major・77小節（約2分）、8トラック。サビは Jersey Club のキック。
//   ファイルは tools/demos/future_bass.py で作り、build/mdaw_render で wav にして音を確かめる。
//   ドラムは Future Bass キット（kits/future-bass）を使う
enum DemoSong { futureBass }

String demoLabel(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'kawaii フューチャーベース（約2分）',
    };

/// 一覧に入るときの曲名
String demoTitle(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'デモ：kawaii フューチャーベース',
    };

/// 同梱のプロジェクトファイル
String demoAsset(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'assets/demos/future_bass.json',
    };
