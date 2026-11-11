# 自作ドラム（2026-11）

`tools/kits/make_pro_drums.py` が書き出すワンショット。録音素材の流用は、下に書いた CC0 の元ファイルだけ。それ以外は NumPy でゼロから合成している（クリック、ピッチが落ちるサインの胴、サブ、ノイズのスネア／クラップ／シェイカー、非整数倍音のハイハット）。

同梱・再配布・商用利用してよい。表示は不要。`LICENSE-SYNTH.txt` と同じ扱い。

## 置き換え（中身が自作合成）

| キット | ファイル | 内容 |
|---|---|---|
| house | kick_house.wav, kick_techno.wav | クリック＋胴＋サブのハウス／テクノキック |
| house | snare_tight_dry.wav, clap_wide.wav, shaker_bright.wav | 胴のあるスネア、広いクラップ、明るいシェイカー |
| future-bass-pro | kick_main.wav, kick_punch.wav, kick_soft.wav, kick_subdeep.wav | 3層のキック |
| future-bass-pro | snare_main.wav, snare_tight.wav, snare_snap.wav | トーン＋ノイズのスネア |
| future-bass-pro | hat_closed.wav, hat_closed_short.wav, hat_open_short.wav | 金属的な部分音＋ノイズのハット |
| future-bass-pro | clap_main.wav, clap_tight.wav, clap_wide.wav | バースト列のクラップ |

TR-808 の実録（CC0）はそのまま残している。

## CC0 実録に自作の胴を足したもの

Acoustic Live の次の3つは、Karoryfer Big Rusty Drums（CC0、出典は `SOURCES_acoustic.txt`）のクローズマイクに、自作の低い胴を重ねた派生。元ファイルはキットには入れず、スクリプトの入力としてリポジトリに残してある。派生も CC0 として再配布する。

| 出力（キットが使う） | 入力（CC0、キットには出さない） |
|---|---|
| kick_full.wav | kick_real.wav |
| snare_full.wav | snare_real.wav |
| rimshot_full.wav | snare_rimshot.wav |

出典 URL は `SOURCES_acoustic.txt` の同じ行。

## kawaii-oneshots

`tools/kits/make_kawaii_oneshots.py` が書く。録音は使わない。

| ファイル | 内容 |
|---|---|
| ah.wav | C4 の倍音列を「あ」のフォルマント（800 / 1250 / 2700 Hz）で短くしたもの |
| oh.wav | 同じソースを「お」（520 / 880 / 2600 Hz）にしたもの |
| piano.wav | C4 の減衰する倍音と短いハンマーノイズ |

ライセンスは自作合成（同梱可、表示不要）。`LICENSE-SYNTH.txt` と同じ。
