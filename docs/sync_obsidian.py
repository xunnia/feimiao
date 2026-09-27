"""把仓库 docs/ 下的 Markdown 镜像到 Obsidian 笔记。

仓库是唯一真相源，Obsidian 只读镜像：
- 只写入目标目录 `记账app/项目文档/`，不碰笔记库里的其他笔记；
- 仓库里删除或改名的文件，镜像里也会删除；
- 内容逐字复制，复制后校验 SHA256。

用法（仓库根目录）：
    python docs/sync_obsidian.py            # 同步
    python docs/sync_obsidian.py --check    # 只检查是否一致，不写入；不一致时退出码为 1
    python docs/sync_obsidian.py --target <目录>  # 换一个镜像目录
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

DOCS_DIR = Path(__file__).resolve().parent
DEFAULT_TARGET = (
    Path.home()
    / "iCloudDrive"
    / "iCloud~md~obsidian"
    / "寻逆笔记"
    / "记账app"
    / "项目文档"
)
MARKER = ".repo-mirror"  # 目标目录里的标记文件，防止误删别的目录


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files() -> dict[str, Path]:
    return {
        p.relative_to(DOCS_DIR).as_posix(): p
        for p in sorted(DOCS_DIR.rglob("*.md"))
    }


def target_files(target: Path) -> dict[str, Path]:
    if not target.exists():
        return {}
    return {
        p.relative_to(target).as_posix(): p
        for p in sorted(target.rglob("*.md"))
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target: Path = args.target

    if not target.parent.exists():
        print(f"找不到 Obsidian 目录：{target.parent}", file=sys.stderr)
        return 2
    if target.exists() and any(target.iterdir()) and not (target / MARKER).exists():
        print(f"目标目录已存在且不是镜像目录（缺少 {MARKER}），为安全起见停止：{target}", file=sys.stderr)
        return 2

    src = source_files()
    dst = target_files(target)
    to_write = [rel for rel, p in src.items() if rel not in dst or sha256(p) != sha256(dst[rel])]
    to_delete = [rel for rel in dst if rel not in src]

    if args.check:
        for rel in to_write:
            print(f"不一致：{rel}")
        for rel in to_delete:
            print(f"多余：{rel}")
        if to_write or to_delete:
            return 1
        print(f"一致：{len(src)} 个文件")
        return 0

    target.mkdir(parents=True, exist_ok=True)
    (target / MARKER).write_text(
        "本目录由仓库 docs/sync_obsidian.py 自动镜像，请到仓库修改，不要在这里编辑。\n",
        encoding="utf-8",
    )
    for rel in to_write:
        out = target / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src[rel], out)
        if sha256(out) != sha256(src[rel]):
            print(f"校验失败：{rel}", file=sys.stderr)
            return 1
        print(f"写入：{rel}")
    for rel in to_delete:
        dst[rel].unlink()
        print(f"删除：{rel}")
    # 清理空子目录
    for d in sorted((p for p in target.rglob("*") if p.is_dir()), reverse=True):
        if not any(d.iterdir()):
            d.rmdir()

    print(f"完成：{len(src)} 个文件，写入 {len(to_write)}，删除 {len(to_delete)} → {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
