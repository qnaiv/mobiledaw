#pragma once

// project.json の読み書き（設計書「編集・Undo・保存形式」）。
// 人が読める JSON。ID は16桁の16進文字列で書く。未知のフィールドは無視し、欠けているものは既定値。

#include <string>

#include "model.h"

namespace mdaw {

std::string projectToJson(const Project& project);

// 失敗したら false を返し、error に理由を入れる（project は変えない）
bool projectFromJson(const std::string& json, Project& project, std::string& error);

// ファイルへの保存は一時ファイルに書いてから差し替える（書きかけで壊れない）
bool saveProjectFile(const Project& project, const std::string& path, std::string& error);
bool loadProjectFile(const std::string& path, Project& project, std::string& error);

} // namespace mdaw
