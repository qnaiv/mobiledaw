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
// ・透明感フューチャーベース「そら色ステップ」：146 BPM・A major・76小節（約2分5秒）。
//   ガラスっぽいベルのイントロ、3-3-2 のスタブ、ハーフタイムのドロップ、固定フォルマントの高い歌。
//   歌入りとインストの2曲。ファイルは tools/demos/buruaka.py。ドラムは Future Bass Pro、キックは A のシンセ。
//   チョップとピアノは自作の Kawaii Oneshots（kits/kawaii-oneshots）
// ・kawaii フューチャーベース「ソーダ色シュガーパレード」：164 BPM・E major（2回目のドロップで F へ半音転調）・
//   76小節（約1分51秒）。チップチューンのリード、オルゴール、跳ねる16分、ワブルコード、合成の歌とチョップ。
//   ファイルは tools/demos/kawaii_fb.py。ドラムは Future Bass Pro、チョップとピアノは Kawaii Oneshots
// ・A.I.テクノ風テクノポップのインスト「ネコミミ☆プロトコル」：148 BPM・D major（ラストサビで全音上げ）・74小節（約2分3秒）。
//   ブレイクビーツ寄りのエレクトロ。主旋律はのこぎり波のリード（モノ＋ポルタメント、遅れて浅いビブラート）で、
//   その呼びかけに矩形波のリードが1オクターブ上の16分で答えるコール＆レスポンス。
//   ♭VI–♭VII で持ち上げるBメロ、Gm6（同主短調の iv）。ファイルは tools/demos/nekomimi.py。ドラムは Chiptune キット＋シンセキック
// ・A.I.テクノ風テクノポップのインスト「メモリー☆シャッフル」：120 BPM・E major（ラストサビで半音上げ）・66小節（約2分15秒）。
//   16分が跳ねるシャッフル。ローズ風エレピとカッティングでシティポップ寄り、サビは王道進行＋経過の減七。
//   主旋律はあたたかいのこぎり波のシンセブラス風リード、合間に矩形波のリードが答える。
//   ファイルは tools/demos/memory_shuffle.py。ドラムは Future Bass Pro キット
enum DemoSong { futureBass, kawaii2, house, lofi, rnb, citySoul, technopop, rock, electronica, buruaka, buruakaInst, kawaiiFb, nekomimi, memoryShuffle }

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
      DemoSong.buruaka => '透明感フューチャーベース「そら色ステップ」（約2分）',
      DemoSong.buruakaInst => '透明感フューチャーベース「そら色ステップ」インスト（約2分）',
      DemoSong.kawaiiFb => 'kawaii フューチャーベース「ソーダ色シュガーパレード」（約1分50秒）',
      DemoSong.nekomimi => 'A.I.テクノ風テクノポップ「ネコミミ☆プロトコル」インスト（約2分）',
      DemoSong.memoryShuffle => 'A.I.テクノ風テクノポップ「メモリー☆シャッフル」インスト（約2分15秒）',
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
      DemoSong.buruaka => 'デモ：そら色ステップ',
      DemoSong.buruakaInst => 'デモ：そら色ステップ（インスト）',
      DemoSong.kawaiiFb => 'デモ：ソーダ色シュガーパレード',
      DemoSong.nekomimi => 'デモ：ネコミミ☆プロトコル',
      DemoSong.memoryShuffle => 'デモ：メモリー☆シャッフル',
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
      DemoSong.buruaka => 'assets/demos/buruaka.json',
      DemoSong.buruakaInst => 'assets/demos/buruaka_inst.json',
      DemoSong.kawaiiFb => 'assets/demos/kawaii_fb.json',
      DemoSong.nekomimi => 'assets/demos/nekomimi.json',
      DemoSong.memoryShuffle => 'assets/demos/memory_shuffle.json',
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
      DemoSong.buruaka => 'Future Bass Pro と Kawaii Oneshots',
      DemoSong.buruakaInst => 'Future Bass Pro と Kawaii Oneshots',
      DemoSong.kawaiiFb => 'Future Bass Pro と Kawaii Oneshots',
      DemoSong.nekomimi => 'Chiptune キット',
      DemoSong.memoryShuffle => 'Future Bass Pro キット',
    };
