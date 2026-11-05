#pragma once

// コード生成するウェーブテーブル（Vital 風の自前実装の土台）。
// ・外部素材は使わない。フレームは倍音プロファイルからの加算合成で作る（ライセンスクリーン）
// ・buildWavetables() は非音声スレッド（Synth::prepare など）で一度だけ呼ぶ。以後は読み取り専用で全ボイス共有
// ・基本周波数に応じて倍音数の上限が違うバンド（ミップ相当）を選び、高音でもエイリアスが増えないようにする
// ・メモリは 7テーブル × 5バンド × 32フレーム × 1024サンプル × 4バイト ≒ 4.6 MB

namespace mdaw {

namespace wavetable {

constexpr int kFrameSize = 1024; // 1フレームのサンプル数
constexpr int kFrames = 32;      // テーブル内のフレーム数（WT_POS で線形補間）
constexpr int kBands = 5;        // 帯域制限バンド。倍音数の上限は 128, 64, 32, 16, 8
constexpr int kTables = 7;       // WT_TABLE の 1〜7（0 は従来オシレーター）

// テーブルを作る（冪等。2回目以降は何もしない）。音声スレッドからは呼ばないこと
void buildWavetables();
bool wavetablesReady() noexcept;

// 1サンプル読む。table は 1〜kTables、pos は 0〜1（フレーム位置）、phase は 0〜1、
// phaseInc は基本周波数 ÷ サンプルレート（バンド選びに使う）。サンプル間・フレーム間とも線形補間。
// 音声スレッドから呼んでよい（確保・ロックなし）
float sampleWavetable(int table, float pos, float phase, float phaseInc) noexcept;

} // namespace wavetable

// WT_WARP の位相リマップ。warp：0=なし、1=bend（正弦で曲げる）、2=squeeze（PWM 的に圧縮）、3=sync（位相の倍率）
// amount は 0〜1。戻り値は 0〜1
float warpPhase(float phase, int warp, float amount) noexcept;

} // namespace mdaw
