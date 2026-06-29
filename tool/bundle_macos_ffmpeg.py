#!/usr/bin/env python3

import shutil
import subprocess
import sys
from pathlib import Path


def run(*args: str) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    return result.stdout


def parse_deps(binary: Path) -> list[str]:
    output = run("/usr/bin/otool", "-L", str(binary))
    deps: list[str] = []
    for line in output.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        dep = stripped.split(" (compatibility version", 1)[0].strip()
        deps.append(dep)
    return deps


def is_bundle_candidate(dep: str) -> bool:
    return dep.startswith("/opt/homebrew/") or dep.startswith("/usr/local/")


def copy_file(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest, follow_symlinks=True)
    mode = dest.stat().st_mode
    dest.chmod(mode | 0o755)


def collect_dependency_graph(roots: list[Path]) -> dict[str, Path]:
    mapping: dict[str, Path] = {}
    queue = list(roots)

    while queue:
        current = queue.pop(0)
        for dep in parse_deps(current):
            if not is_bundle_candidate(dep):
                continue
            if dep in mapping:
                continue
            dep_path = Path(dep)
            if not dep_path.exists():
                raise FileNotFoundError(f"缺少依赖库: {dep}")
            mapping[dep] = dep_path
            queue.append(dep_path)

    return mapping


def main() -> int:
    if len(sys.argv) != 3:
        print("用法: python3 tool/bundle_macos_ffmpeg.py <ffmpeg_bin_dir> <runtime_dest>")
        return 1

    source_bin_dir = Path(sys.argv[1]).resolve()
    runtime_dest = Path(sys.argv[2]).resolve()
    bin_dest = runtime_dest / "bin"
    lib_dest = runtime_dest / "lib"

    ffmpeg_src = source_bin_dir / "ffmpeg"
    ffprobe_src = source_bin_dir / "ffprobe"
    if not ffmpeg_src.exists() or not ffprobe_src.exists():
        raise FileNotFoundError(f"未找到 ffmpeg/ffprobe: {source_bin_dir}")

    if runtime_dest.exists():
        shutil.rmtree(runtime_dest)
    bin_dest.mkdir(parents=True, exist_ok=True)
    lib_dest.mkdir(parents=True, exist_ok=True)

    ffmpeg_dest = bin_dest / "ffmpeg"
    ffprobe_dest = bin_dest / "ffprobe"
    copy_file(ffmpeg_src, ffmpeg_dest)
    copy_file(ffprobe_src, ffprobe_dest)

    dep_map = collect_dependency_graph([ffmpeg_src, ffprobe_src])
    copied_libs: dict[str, Path] = {}
    for old_dep, src_path in dep_map.items():
        dest_path = lib_dest / src_path.name
        copy_file(src_path, dest_path)
        copied_libs[old_dep] = dest_path

    print(f"FFmpeg 运行时已嵌入: {runtime_dest}")
    print(f"- ffmpeg: {ffmpeg_dest}")
    print(f"- ffprobe: {ffprobe_dest}")
    print(f"- dylibs: {len(copied_libs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
