#!/usr/bin/env python3
"""kits/*/kit.json を読んで kits/index.json を作る（アプリはこれを見てキットを一覧・ダウンロードする）。

  python3 tools/kits/build_index.py          # index.json を書き直す
  python3 tools/kits/build_index.py --check  # ずれていたら終了コード 1（CI 用）
"""
import hashlib
import json
import os
import re
import sys
import wave

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "kits")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")


def fail(msg):
    print("エラー:", msg, file=sys.stderr)
    sys.exit(1)


def check_wav(path):
    """WAV として読めるかだけ確かめる（float の wav は wave で読めないので RIFF/WAVE の頭だけ見る）"""
    with open(path, "rb") as f:
        head = f.read(12)
    if head[:4] != b"RIFF" or head[8:12] != b"WAVE":
        fail(f"WAV ではありません: {path}")
    try:
        with wave.open(path) as w:
            return w.getnframes() / w.getframerate()
    except wave.Error:
        return None  # 32bit float など。アプリ（コア）では読める


def build():
    kits = []
    for kid in sorted(os.listdir(ROOT)):
        d = os.path.join(ROOT, kid)
        if not os.path.isdir(d) or kid.startswith("_"):
            continue  # _licenses など
        meta_path = os.path.join(d, "kit.json")
        if not os.path.isfile(meta_path):
            fail(f"{kid}/kit.json がありません")
        if not ID_RE.match(kid):
            fail(f"キットの ID は英小文字・数字・- だけにしてください: {kid}")
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
        sounds = meta.get("sounds") or []
        if not sounds:
            fail(f"{kid}: sounds が空です")
        files = ["kit.json"]
        for i, s in enumerate(sounds):
            rel = s.get("file")
            if not rel or ".." in rel.split("/") or rel.startswith("/"):
                fail(f"{kid}: sounds[{i}].file が正しくありません")
            p = os.path.join(d, rel)
            if not os.path.isfile(p):
                fail(f"{kid}: {rel} がありません")
            check_wav(p)
            note = s.get("note", 36 + i)
            if not (isinstance(note, int) and 0 <= note <= 127):
                fail(f"{kid}: sounds[{i}].note は 0〜127")
            if rel not in files:
                files.append(rel)
        entries, total = [], 0
        for rel in files:
            p = os.path.join(d, rel)
            data = open(p, "rb").read()
            total += len(data)
            entries.append({"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        kits.append({
            "id": kid,
            "name": meta.get("name", kid),
            "version": int(meta.get("version", 1)),
            "author": meta.get("author", ""),
            "license": meta.get("license", ""),
            "description": meta.get("description", ""),
            "sounds": len(sounds),
            "size": total,
            "files": entries,
        })
    return {"format": "mobiledaw-kits", "version": 1, "kits": kits}


def main():
    out = os.path.join(ROOT, "index.json")
    text = json.dumps(build(), ensure_ascii=False, indent=1) + "\n"
    if "--check" in sys.argv:
        current = open(out, encoding="utf-8").read() if os.path.exists(out) else ""
        if current != text:
            fail("kits/index.json が古いです。python3 tools/kits/build_index.py を実行してコミットしてください")
        print("kits/index.json は最新です")
        return
    with open(out, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{out} を更新しました（{len(json.loads(text)['kits'])} キット）")


if __name__ == "__main__":
    main()
