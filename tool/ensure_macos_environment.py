#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Dict, Optional


FLUTTER_VERSION = "3.44.2"
FLUTTER_CHANNEL = "stable"
FLUTTER_RELEASES_URL = (
    "https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json"
)
FFMPEG_INFO_URLS = {
    "ffmpeg": "https://evermeet.cx/ffmpeg/info/ffmpeg/release",
    "ffprobe": "https://evermeet.cx/ffmpeg/info/ffprobe/release",
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _toolchain_dir() -> Path:
    return _repo_root() / ".toolchain"


def _downloads_dir() -> Path:
    path = _toolchain_dir() / "downloads"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _run(
    command: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    env: Optional[Dict[str, str]] = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env=env,
    )


def _download(url: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".part")
    if tmp.exists():
        tmp.unlink()
    print(f"下载: {url}")
    _run(
        [
            "curl",
            "--fail",
            "--location",
            "--retry",
            "3",
            "--connect-timeout",
            "30",
            "--output",
            str(tmp),
            url,
        ]
    )
    tmp.replace(target)


def _load_json(url: str) -> dict:
    result = _run(
        [
            "curl",
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--retry",
            "3",
            url,
        ],
        capture=True,
    )
    return json.loads(result.stdout)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _platform_tag() -> str:
    machine = platform.machine().lower()
    if machine in {"x86_64", "amd64"}:
        return "macos-x64"
    if machine in {"arm64", "aarch64"}:
        return "macos-arm64"
    raise RuntimeError(f"暂不支持的 macOS 架构: {machine}")


def _current_flutter_version(flutter: Path) -> Optional[str]:
    if not flutter.exists():
        return None
    try:
        result = _run([str(flutter), "--version"], capture=True)
    except Exception:
        return None
    first_line = result.stdout.splitlines()[0] if result.stdout else ""
    match = re.search(r"Flutter\s+([0-9]+\.[0-9]+\.[0-9]+)", first_line)
    return match.group(1) if match else None


def ensure_flutter() -> Path:
    system_flutter = shutil.which("flutter")
    if system_flutter:
        version = _current_flutter_version(Path(system_flutter))
        if version == FLUTTER_VERSION:
            print(f"Flutter 已就绪: {system_flutter} ({version})")
            return Path(system_flutter)

    local_flutter = _toolchain_dir() / "flutter" / "bin" / "flutter"
    version = _current_flutter_version(local_flutter)
    if version == FLUTTER_VERSION:
        print(f"Flutter 已就绪: {local_flutter} ({version})")
        return local_flutter

    releases = _load_json(FLUTTER_RELEASES_URL)
    archive = None
    for release in releases.get("releases", []):
        if (
            release.get("version") == FLUTTER_VERSION
            and release.get("channel") == FLUTTER_CHANNEL
        ):
            archive = release.get("archive")
            break
    if not archive:
        raise RuntimeError(f"未找到 Flutter {FLUTTER_VERSION} {FLUTTER_CHANNEL} 归档")

    url = f"{releases['base_url'].rstrip('/')}/{archive}"
    archive_path = _downloads_dir() / Path(archive).name
    if not archive_path.exists():
        _download(url, archive_path)

    target_root = _toolchain_dir()
    extracted = target_root / "flutter"
    if extracted.exists():
        shutil.rmtree(extracted)
    print(f"解压 Flutter SDK: {archive_path}")
    with zipfile.ZipFile(archive_path) as zf:
        zf.extractall(target_root)

    version = _current_flutter_version(local_flutter)
    if version != FLUTTER_VERSION:
        raise RuntimeError(f"Flutter SDK 下载后版本不匹配: {version}")

    print(f"Flutter 下载完成: {local_flutter} ({version})")
    return local_flutter


def _binary_version(path: Path, name: str) -> Optional[str]:
    if not path.exists():
        return None
    try:
        result = _run([str(path), "-version"], capture=True)
    except Exception:
        return None
    first_line = result.stdout.splitlines()[0] if result.stdout else ""
    match = re.search(rf"{name}\s+version\s+([^\s]+)", first_line)
    return match.group(1) if match else None


def _matches_release_version(actual: Optional[str], expected: str) -> bool:
    return actual == expected or (actual is not None and actual.startswith(f"{expected}-"))


def _extract_binary(zip_path: Path, binary_name: str, target: Path) -> None:
    with zipfile.ZipFile(zip_path) as zf:
        member = None
        for candidate in zf.namelist():
            if Path(candidate).name == binary_name and not candidate.endswith("/"):
                member = candidate
                break
        if member is None:
            raise RuntimeError(f"{zip_path} 内未找到 {binary_name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(member) as source, target.open("wb") as dest:
            shutil.copyfileobj(source, dest)
    mode = target.stat().st_mode
    target.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    _run(["xattr", "-dr", "com.apple.quarantine", str(target)], check=False)


def ensure_ffmpeg() -> Path:
    tag = _platform_tag()
    if tag != "macos-x64":
        raise RuntimeError("当前下载源只提供 macOS Intel 静态 FFmpeg；此脚本当前仅支持 macos-x64")

    ffmpeg_info = _load_json(FFMPEG_INFO_URLS["ffmpeg"])
    ffprobe_info = _load_json(FFMPEG_INFO_URLS["ffprobe"])
    if ffmpeg_info["version"] != ffprobe_info["version"]:
        raise RuntimeError("ffmpeg 与 ffprobe release 版本不一致")
    version = ffmpeg_info["version"]

    root = _toolchain_dir() / "ffmpeg" / tag
    bin_dir = root / "bin"
    ffmpeg = bin_dir / "ffmpeg"
    ffprobe = bin_dir / "ffprobe"
    manifest_path = root / "manifest.json"
    if _matches_release_version(
        _binary_version(ffmpeg, "ffmpeg"),
        version,
    ) and _matches_release_version(
        _binary_version(ffprobe, "ffprobe"),
        version,
    ) and manifest_path.exists():
        print(f"FFmpeg 已就绪: {bin_dir} ({version})")
        return root

    archives = {}
    for name, info in {"ffmpeg": ffmpeg_info, "ffprobe": ffprobe_info}.items():
        url = info["download"]["zip"]["url"]
        archive_path = _downloads_dir() / Path(url).name
        if not archive_path.exists():
            _download(url, archive_path)
        archives[name] = archive_path

    if bin_dir.exists():
        shutil.rmtree(bin_dir)
    _extract_binary(archives["ffmpeg"], "ffmpeg", ffmpeg)
    _extract_binary(archives["ffprobe"], "ffprobe", ffprobe)

    ffmpeg_version = _binary_version(ffmpeg, "ffmpeg")
    ffprobe_version = _binary_version(ffprobe, "ffprobe")
    if not _matches_release_version(
        ffmpeg_version,
        version,
    ) or not _matches_release_version(ffprobe_version, version):
        raise RuntimeError(
            f"FFmpeg 下载后版本不匹配: ffmpeg={ffmpeg_version}, ffprobe={ffprobe_version}, expected={version}"
        )

    manifest = {
        "platform": tag,
        "version": version,
        "ffmpeg_reported_version": ffmpeg_version,
        "ffprobe_reported_version": ffprobe_version,
        "source": "https://evermeet.cx/ffmpeg/",
        "ffmpeg": {
            "url": ffmpeg_info["download"]["zip"]["url"],
            "archive_sha256": _sha256(archives["ffmpeg"]),
            "binary_sha256": _sha256(ffmpeg),
        },
        "ffprobe": {
            "url": ffprobe_info["download"]["zip"]["url"],
            "archive_sha256": _sha256(archives["ffprobe"]),
            "binary_sha256": _sha256(ffprobe),
        },
    }
    root.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"FFmpeg 下载完成: {bin_dir} ({version})")
    return root


def install_ffmpeg_runtime(release_dir: Path) -> Path:
    source_root = ensure_ffmpeg()
    tag = source_root.name
    target_root = release_dir / "runtime" / "ffmpeg" / tag
    if target_root.exists():
        shutil.rmtree(target_root)
    target_root.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source_root, target_root)
    for binary in (target_root / "bin").iterdir():
        if binary.is_file():
            mode = binary.stat().st_mode
            binary.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            _run(["xattr", "-dr", "com.apple.quarantine", str(binary)], check=False)
    print(f"已安装 FFmpeg runtime: {target_root}")
    return target_root


def main() -> int:
    parser = argparse.ArgumentParser(description="补齐 macOS 构建和运行环境文件")
    parser.add_argument("--skip-flutter", action="store_true", help="不检查/下载 Flutter SDK")
    parser.add_argument("--skip-ffmpeg", action="store_true", help="不检查/下载 FFmpeg")
    parser.add_argument(
        "--install-runtime-to",
        type=Path,
        help="把 FFmpeg runtime 复制到指定发布目录",
    )
    args = parser.parse_args()

    if sys.platform != "darwin":
        raise SystemExit("该脚本只用于 macOS 环境")

    if not args.skip_flutter:
        ensure_flutter()
    if args.install_runtime_to is not None:
        install_ffmpeg_runtime(args.install_runtime_to.resolve())
    elif not args.skip_ffmpeg:
        ensure_ffmpeg()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
