# ドラムキット

アプリの「キットを探す」に並ぶドラムキット。APK には入れず、アプリがここ（GitHub の main）からダウンロードする。

## 追加のしかた

1. `kits/<キットのID>/` を作る（ID は英小文字・数字・`-` だけ。例 `kawaii-kit-01`）
2. wav を入れる
   - 形式：WAV（16/24bit 整数か 32bit float）、モノラルかステレオ、44.1kHz か 48kHz
   - 1ファイル 1音（ワンショット）。頭の無音は切っておく（遅れて聞こえるため）
   - 1キットの合計は 20MB くらいまでが目安
3. `kit.json` を書く（下の例）
4. `python3 tools/kits/build_index.py` を実行して `kits/index.json` を更新する
5. まとめてコミットして main に push する（CI が index のずれを見つけたら失敗する）

## kit.json

```json
{
  "name": "Kawaii Kit 01",
  "version": 1,
  "author": "Qnaiv",
  "license": "CC0-1.0",
  "description": "kawaii future bass 向け",
  "sounds": [
    {"file": "kick.wav",     "name": "Kick",       "note": 36},
    {"file": "snare.wav",    "name": "Snare",      "note": 38},
    {"file": "clap.wav",     "name": "Clap",       "note": 39, "gain": 0.9},
    {"file": "hat_c.wav",    "name": "Closed Hat", "note": 42, "choke": 1},
    {"file": "hat_o.wav",    "name": "Open Hat",   "note": 46, "choke": 1}
  ]
}
```

| 項目 | 意味 |
|---|---|
| `name` | アプリに出る名前 |
| `version` | 中身を変えたら 1 増やす（アプリに「更新」が出る） |
| `author` / `license` / `description` | キットの説明。license は配布してよいもの（CC0 など）だけ。自作合成ドラムの出どころは `_licenses/SYNTH_DRUMS.md` |
| `sounds[].file` | このフォルダの中の wav（サブフォルダ可） |
| `sounds[].name` | ピアノロールの列に出る名前 |
| `sounds[].note` | 割り当てる音程（MIDI 0〜127）。省くと 36 から順に。GM ドラムの番号に合わせると MIDI 書き出しでも扱いやすい（Kick 36・Snare 38・Clap 39・Closed Hat 42・Open Hat 46・Crash 49・Ride 51 など） |
| `sounds[].gain` | 音量（0〜2、省くと 1） |
| `sounds[].choke` | 同じ番号どうしは、後から鳴った音が前の音を止める（ハイハットの開・閉など）。0 か省くと止めない |

同じ `note` に2つ以上の音を割り当てると、同時に鳴る（重ねる用）。
