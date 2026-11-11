// メニュー「デモ曲」で入る曲。同梱のプロジェクトファイル（assets/demos/）を一覧に入れて開く。
// 取り込み先の ID はデモごとに固定（demoProjectId）なので、開くたびに一覧へ増えず、
// 一度取り込んだデモへの編集はそのまま残る。
// ・kawaii フューチャーベース：150 BPM・F major・77小節（約2分）、8トラック。サビは Jersey Club のキック。
//   ファイルは tools/demos/future_bass.py で作り、build/mdaw_render で wav にして音を確かめる。
//   ドラムは Future Bass キット（kits/future-bass）を使う
// ・kawaii フューチャーベース2：155 BPM・D major・56小節（約1分27秒）、12トラック。本格 FB プリセット
//   （FB Chords 9th／FB Vocal Lead／FB Wobble Bass 等）と 9th ボイシング、エンジン拡張
//   （グライド＋モノ、テンポ同期 LFO、キートラッキング）を使った第2弾。既存曲とはキー・進行・メロディが別。
//   ファイルは tools/demos/kawaii2.py で作る。ドラムは Future Bass Pro キット（kits/future-bass-pro）を使う
// ・ハウス：124 BPM・A minor・32小節（約1分）、7トラック。四つ打ち、裏拍のオープンハット、オフビートベース。キーズとリードはウェーブテーブル使用。
//   ファイルは tools/demos/house.py で作る。ドラムは House キット（kits/house）を使う
// ・Lo-fi：84 BPM・D minor・24小節（約1分9秒）、7トラック。スウィングするドラム、ローパスの効いたコード。
//   ファイルは tools/demos/lofi.py で作る。ドラムは Lo-fi Boom Bap キット（kits/lofi-boombap）を使う
// ・R&B：92 BPM・E♭ major・32小節（約1分23秒）、8トラック。サイドスティックとライドのスローなグルーヴ。
//   ファイルは tools/demos/rnb.py で作る。R&B 専用キットは無いので、生ドラムの
//   Acoustic Live キット（kits/acoustic-live）を使う（スティックとライドがスローな曲に合うため）
// ・シティソウル：96 BPM・D minor・48小節（2分）、8トラック。Just the Two of Us 系の IVM7 → III7 → vim7 の流れに
//   書き下ろしのメロディ（短い動機のくり返しとずらし）。ローズ風キーズ・歌うリード（モノ＋グライド）・ビブラフォン。
//   ファイルは tools/demos/city_soul.py で作る。ドラムは Acoustic Live キット（kits/acoustic-live）
// ・テクノポップ「ネオン・シグナル」：128 BPM・B♭ major・38小節（約1分11秒）。シンセが日本語の歌詞を歌う。
//   ファイルは tools/demos/technopop.py（singer.py / vowels.py）。ドラムは House キット
// ・ロック「オーバードライブ」：140 BPM・E minor・42小節（約1分12秒）。歪んだギターとトークボックスのリード。
//   ファイルは tools/demos/rock.py。ドラムは Acoustic Live キット
// ・エレクトロニカ「グラス・ガーデン」：112 BPM・D minor・38小節（約1分21秒）。クワイアパッドとボーカルチョップ。
//   ファイルは tools/demos/electronica.py。ドラムは Future Bass Pro キット（キックはキーに合わせたシンセ）
enum DemoSong { futureBass, kawaii2, house, lofi, rnb, citySoul, technopop, rock, electronica }

/// デモ曲の取り込み先の曲 ID（デモごとに固定。曲の ID 体系は ProjectLibrary 参照）
String demoProjectId(DemoSong d) => 'demo-${d.name}';

String demoLabel(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'kawaii フューチャーベース（約2分）',
      DemoSong.kawaii2 => 'kawaii フューチャーベース2（約1分半）',
      DemoSong.house => 'ハウス（約1分）',
      DemoSong.lofi => 'Lo-fi（約1分）',
      DemoSong.rnb => 'R&B（約1分半）',
      DemoSong.citySoul => 'シティソウル（2分）',
      DemoSong.technopop => 'テクノポップ「ネオン・シグナル」（約1分）',
      DemoSong.rock => 'ロック「オーバードライブ」（約1分）',
      DemoSong.electronica => 'エレクトロニカ「グラス・ガーデン」（約1分半）',
    };

/// 一覧に入るときの曲名
String demoTitle(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'デモ：kawaii フューチャーベース',
      DemoSong.kawaii2 => 'デモ：kawaii フューチャーベース2',
      DemoSong.house => 'デモ：ハウス',
      DemoSong.lofi => 'デモ：Lo-fi',
      DemoSong.rnb => 'デモ：R&B',
      DemoSong.citySoul => 'デモ：シティソウル',
      DemoSong.technopop => 'デモ：ネオン・シグナル',
      DemoSong.rock => 'デモ：オーバードライブ',
      DemoSong.electronica => 'デモ：グラス・ガーデン',
    };

/// 同梱のプロジェクトファイル
String demoAsset(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'assets/demos/future_bass.json',
      DemoSong.kawaii2 => 'assets/demos/kawaii2.json',
      DemoSong.house => 'assets/demos/house.json',
      DemoSong.lofi => 'assets/demos/lofi.json',
      DemoSong.rnb => 'assets/demos/rnb.json',
      DemoSong.citySoul => 'assets/demos/city_soul.json',
      DemoSong.technopop => 'assets/demos/technopop.json',
      DemoSong.rock => 'assets/demos/rock.json',
      DemoSong.electronica => 'assets/demos/electronica.json',
    };

/// メニューに出すキット名
String demoKitName(DemoSong d) => switch (d) {
      DemoSong.futureBass => 'Future Bass キット',
      DemoSong.kawaii2 => 'Future Bass Pro キット',
      DemoSong.house => 'House キット',
      DemoSong.lofi => 'Lo-fi Boom Bap キット',
      DemoSong.rnb => 'Acoustic Live キット',
      DemoSong.citySoul => 'Acoustic Live キット',
      DemoSong.technopop => 'House キット',
      DemoSong.rock => 'Acoustic Live キット',
      DemoSong.electronica => 'Future Bass Pro キット',
    };
