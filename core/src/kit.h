#pragma once

// ドラムキット（kits/<id>/kit.json と wav）。読み込みはコアスレッドで行い、
// 出来上がった Kit は変更しない（再生用スナップショットから shared_ptr で指す）。

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace mdaw {

struct KitSound {
    std::string name;
    int note = 36;
    float gain = 1.0f;
    int choke = 0;              // 同じ番号の音どうしで止め合う（0 = なし）
    double sampleRate = 48000.0;
    std::vector<float> left;    // モノラルなら right は空
    std::vector<float> right;
    int frames() const noexcept { return static_cast<int>(left.size()); }
};

struct Kit {
    std::string id;
    std::string name;
    std::vector<KitSound> sounds;
};

using KitPtr = std::shared_ptr<const Kit>;

// dir/kit.json を読む。失敗したら nullptr と error
KitPtr loadKit(const std::string& dir, const std::string& id, std::string& error);

// ID → 読み込んだキット。root/<id>/ から読み、同じ ID は使い回す
class KitCache {
public:
    void setRoot(std::string root);
    const std::string& root() const noexcept { return root_; }
    KitPtr get(const std::string& id);          // 無い・読めないなら nullptr（理由は error(id)）
    std::string error(const std::string& id) const;
    void clear();                               // ダウンロードし直したあとに呼ぶ

private:
    std::string root_;
    std::map<std::string, KitPtr> loaded_;
    std::map<std::string, std::string> errors_;
};

bool isValidKitId(const std::string& id) noexcept;

} // namespace mdaw
