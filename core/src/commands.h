#pragma once

// 編集コマンド（設計書「編集・Undo・保存形式」）。
// すべての編集はコマンドとしてモデルに適用し、Undo は revert で戻す。
// apply は対象が見つからない・意味のない操作なら false を返し、モデルを変えない。

#include <memory>
#include <string>
#include <vector>

#include "model.h"

namespace mdaw {

class Command {
public:
    virtual ~Command() = default;
    virtual bool apply(Project& p) = 0;
    virtual void revert(Project& p) = 0;
    virtual const char* name() const = 0;
};

using CommandPtr = std::unique_ptr<Command>;

// ---- ノート -----------------------------------------------------------------

// ノートを追加する。id が 0 のノートには新しい id を振る（振った id は addedIds() で分かる）。
class AddNotes final : public Command {
public:
    AddNotes(Id clipId, std::vector<Note> notes) : clipId_(clipId), notes_(std::move(notes)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "AddNotes"; }
    std::vector<Id> addedIds() const;

private:
    Id clipId_;
    std::vector<Note> notes_;
};

class DeleteNotes final : public Command {
public:
    DeleteNotes(Id clipId, std::vector<Id> noteIds) : clipId_(clipId), ids_(std::move(noteIds)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "DeleteNotes"; }

private:
    Id clipId_;
    std::vector<Id> ids_;
    std::vector<Note> removed_;
};

// まとめて動かす。はみ出す場合は、全体がクリップと音域に収まる範囲まで移動量を詰める。
class MoveNotes final : public Command {
public:
    MoveNotes(Id clipId, std::vector<Id> noteIds, int64_t deltaTicks, int deltaPitch)
        : clipId_(clipId), ids_(std::move(noteIds)), dTick_(deltaTicks), dPitch_(deltaPitch) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "MoveNotes"; }
    int64_t appliedDeltaTicks() const noexcept { return appliedTick_; }
    int appliedDeltaPitch() const noexcept { return appliedPitch_; }

private:
    void shift(Project& p, int64_t dt, int dp);
    Id clipId_;
    std::vector<Id> ids_;
    int64_t dTick_;
    int dPitch_;
    int64_t appliedTick_ = 0;
    int appliedPitch_ = 0;
};

// 長さを変える（最短は 1/64 拍）。
class ResizeNotes final : public Command {
public:
    static constexpr int64_t kMinLength = kPpq / 16;
    ResizeNotes(Id clipId, std::vector<Id> noteIds, int64_t deltaTicks)
        : clipId_(clipId), ids_(std::move(noteIds)), delta_(deltaTicks) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "ResizeNotes"; }

private:
    Id clipId_;
    std::vector<Id> ids_;
    int64_t delta_;
    std::vector<std::pair<Id, int64_t>> oldLengths_;
};

// ---- クリップと配置 ----------------------------------------------------------

// 新しいクリップを作り、指定小節に置く（縦タイムラインの空きマスをタップしたとき）
class CreateClip final : public Command {
public:
    CreateClip(Id trackId, int startBar, int lengthBars) : trackId_(trackId), startBar_(startBar), lengthBars_(lengthBars) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "CreateClip"; }
    Id clipId() const noexcept { return clip_.id; }
    Id placementId() const noexcept { return placement_.id; }

private:
    Id trackId_;
    int startBar_;
    int lengthBars_;
    Clip clip_;
    Placement placement_;
};

// 同じクリップをもう一つ置く（複製 = 同じ clipId を参照する配置を増やす）
class PlaceClip final : public Command {
public:
    PlaceClip(Id clipId, int startBar) : clipId_(clipId), startBar_(startBar) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "PlaceClip"; }
    Id placementId() const noexcept { return placement_.id; }

private:
    Id clipId_;
    int startBar_;
    Placement placement_;
};

// クリップを別パターンとして複製する：中身（ノート・オートメーション）を複製した
// 新しいクリップを作って指定小節に置く。複製側を編集しても元のクリップには影響しない
class CloneClip final : public Command {
public:
    CloneClip(Id clipId, int startBar) : clipId_(clipId), startBar_(startBar) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "CloneClip"; }
    Id clipId() const noexcept { return clone_.id; }
    Id placementId() const noexcept { return placement_.id; }

private:
    Id clipId_;
    int startBar_;
    Clip clone_;
    Placement placement_;
};

// 配置を外す。どこからも参照されなくなったクリップも一緒に消す（Undo で戻る）
class RemovePlacement final : public Command {
public:
    explicit RemovePlacement(Id placementId) : placementId_(placementId) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "RemovePlacement"; }

private:
    Id placementId_;
    Placement removed_;
    size_t index_ = 0;
    bool removedClip_ = false;
    Clip clip_;
    size_t clipIndex_ = 0;
};

class MovePlacement final : public Command {
public:
    MovePlacement(Id placementId, int newStartBar) : placementId_(placementId), newStart_(newStartBar) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "MovePlacement"; }

private:
    Id placementId_;
    int newStart_;
    int oldStart_ = 0;
};

// クリップの長さを小節単位で変える。そのクリップの配置（複製も）はすべて同じ長さになる。
// 縮めてはみ出したノートは消える（Undo で戻る）。伸ばして他のクリップとぶつかるなら何もしない。
class ResizeClip final : public Command {
public:
    static constexpr int kMaxBars = 64;
    ResizeClip(Id clipId, int lengthBars) : clipId_(clipId), bars_(lengthBars) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "ResizeClip"; }

private:
    Id clipId_;
    int bars_;
    int64_t oldLength_ = 0;
    std::vector<std::pair<Id, int>> oldPlacementBars_;
    std::vector<Note> removed_;
    std::vector<AutomationLane> oldAutomation_; // 縮めたときに切り落とした分を Undo で戻すため
};

// クリップのオートメーションの1レーンを丸ごと差し替える（空のレーンなら削除）。
// ポイントは apply の中で整える（並べ替え・範囲外の削除・値の丸め）。変わらなければ false。
class SetClipAutomation final : public Command {
public:
    SetClipAutomation(Id clipId, AutomationLane lane) : clipId_(clipId), next_(std::move(lane)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetClipAutomation"; }

private:
    Id clipId_;
    AutomationLane next_;
    AutomationLane old_;
    bool hadOld_ = false;
};

// ---- トラックと全体 -----------------------------------------------------------

class AddTrack final : public Command {
public:
    explicit AddTrack(std::string name, uint32_t color) : name_(std::move(name)), color_(color) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "AddTrack"; }
    Id trackId() const noexcept { return track_.id; }

private:
    std::string name_;
    uint32_t color_;
    Track track_;
};

// トラックの音源をドラムキットにする（kitId が空ならシンセに戻す）
class SetTrackKit final : public Command {
public:
    SetTrackKit(Id trackId, std::string kitId) : trackId_(trackId), kitId_(std::move(kitId)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetTrackKit"; }

private:
    Id trackId_;
    std::string kitId_;
    std::string old_;
};

// トラックの楽器をサンプラーにする（設定一式の差し替え。next.kitId が空ならサンプラーをやめる）
class SetTrackSampler final : public Command {
public:
    SetTrackSampler(Id trackId, SamplerSettings next) : trackId_(trackId), next_(std::move(next)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetTrackSampler"; }

private:
    Id trackId_;
    SamplerSettings next_;
    SamplerSettings old_;
};

// 曲の名前（1〜64バイト、前後の空白は落とす）
class SetProjectTitle final : public Command {
public:
    explicit SetProjectTitle(std::string title) : title_(std::move(title)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override { p.title = old_; }
    const char* name() const override { return "SetProjectTitle"; }

private:
    std::string title_;
    std::string old_;
};

// マスターバス（音量・グルー・ソフトクリップ・天井）
class SetMaster final : public Command {
public:
    explicit SetMaster(MasterParams next) : next_(next) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetMaster"; }

private:
    MasterParams next_;
    MasterParams old_;
};

// AUX リターン（リバーブとディレイ）
class SetAux final : public Command {
public:
    explicit SetAux(AuxParams next) : next_(next) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetAux"; }

private:
    AuxParams next_;
    AuxParams old_;
};

// トラックの音量・パン・ミュート・ソロをまとめて変える
class SetTrackMixer final : public Command {
public:
    SetTrackMixer(Id trackId, Mixer mixer) : trackId_(trackId), next_(mixer) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetTrackMixer"; }

private:
    Id trackId_;
    Mixer next_;
    Mixer old_;
};

class RenameTrack final : public Command {
public:
    RenameTrack(Id trackId, std::string name) : trackId_(trackId), name_(std::move(name)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "RenameTrack"; }

private:
    Id trackId_;
    std::string name_;
    std::string old_;
};

class SetTempo final : public Command {
public:
    explicit SetTempo(double bpm) : bpm_(bpm) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetTempo"; }

private:
    double bpm_;
    double old_ = 120.0;
};

// 曲のキー（ルート音とスケールの保存名）。スケール名はコアでは中身を見ず、そのまま保持する
class SetKey final : public Command {
public:
    SetKey(int root, std::string scale) : root_(root), scale_(std::move(scale)) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetKey"; }

private:
    int root_;
    std::string scale_;
    int oldRoot_ = 0;
    std::string oldScale_;
};

// シンセのパラメータ（マクロを離した時に「開始値→終了値」の1コマンドにする）
class SetTrackSynthParam final : public Command {
public:
    SetTrackSynthParam(Id trackId, int paramId, float value) : trackId_(trackId), paramId_(paramId), value_(value) {}
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return "SetTrackSynthParam"; }

private:
    Id trackId_;
    int paramId_;
    float value_;
    float old_ = 0.0f;
};

// 複数のコマンドを1つの Undo 単位にまとめる（「線」ツールで生まれた複数ノートなど）
class CompoundCommand final : public Command {
public:
    explicit CompoundCommand(const char* label) : label_(label) {}
    void add(CommandPtr c) { children_.push_back(std::move(c)); }
    // すでにモデルへ適用済みのコマンドを加える（ジェスチャー中に1つずつ反映し、最後にまとめる用）
    void addApplied(CommandPtr c) {
        children_.push_back(std::move(c));
        applied_ = children_.size();
    }
    bool apply(Project& p) override;
    void revert(Project& p) override;
    const char* name() const override { return label_; }
    bool empty() const noexcept { return children_.empty(); }

private:
    const char* label_;
    std::vector<CommandPtr> children_;
    size_t applied_ = 0;
};

} // namespace mdaw
