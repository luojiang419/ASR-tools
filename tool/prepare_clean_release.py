#!/usr/bin/env python3

import json
import re
import shutil
import sqlite3
import sys
from pathlib import Path
from typing import Optional, Tuple


def _reset_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _load_schema_sql(repo_root: Path) -> list[str]:
    source = (repo_root / "lib" / "services" / "database_service.dart").read_text(
        encoding="utf-8"
    )

    tables = re.findall(r"await db\.execute\('''\n(.*?)\n\s*'''\);", source, re.S)
    indexes = re.findall(
        r"await db\.execute\(\s*'((?:CREATE INDEX|CREATE UNIQUE INDEX)[^']+)'\s*,?\s*\);",
        source,
        re.S,
    )

    statements = [
        sql.strip()
        for sql in tables
        if sql.strip().upper().startswith("CREATE TABLE")
    ]
    statements.extend(
        sql.strip()
        for sql in indexes
        if sql.strip().upper().startswith("CREATE INDEX")
        or sql.strip().upper().startswith("CREATE UNIQUE INDEX")
    )
    return statements


def _load_db_version(repo_root: Path) -> int:
    source = (repo_root / "lib" / "core" / "constants.dart").read_text(
        encoding="utf-8"
    )
    match = re.search(r"static const int dbVersion = (\d+);", source)
    if match is None:
        raise RuntimeError("未能从 constants.dart 解析数据库版本号")
    return int(match.group(1))


def _initialize_clean_database(db_path: Path, repo_root: Path) -> None:
    db_version = _load_db_version(repo_root)
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        for statement in _load_schema_sql(repo_root):
            conn.execute(statement)
        conn.execute(f"PRAGMA user_version = {db_version}")
        conn.commit()
    finally:
        conn.close()


def _find_release_layout(release_dir: Path) -> Optional[Tuple[Path, Path]]:
    windows_exe = release_dir / "asr_tools.exe"
    if windows_exe.exists():
        return windows_exe, release_dir / "data"

    app_dir = release_dir / "asr_tools.app"
    if release_dir.suffix == ".app":
        app_dir = release_dir

    macos_exe = app_dir / "Contents" / "MacOS" / "asr_tools"
    if macos_exe.exists():
        return macos_exe, app_dir.parent / "data"

    return None


def main() -> int:
    if len(sys.argv) != 2:
        print("用法: python3 tool/prepare_clean_release.py <release_dir>")
        return 1

    repo_root = Path(__file__).resolve().parent.parent
    release_dir = Path(sys.argv[1]).resolve()

    if not release_dir.exists():
        print(f"发布目录不存在: {release_dir}")
        return 1

    layout = _find_release_layout(release_dir)
    if layout is None:
        print(f"未找到发布程序: {release_dir}/asr_tools.exe 或 asr_tools.app")
        return 1
    exe_path, data_dir = layout

    config_dir = data_dir / "config"
    database_dir = data_dir / "database"
    projects_dir = data_dir / "projects"
    temp_dir = data_dir / "temp"

    data_dir.mkdir(parents=True, exist_ok=True)
    _reset_dir(config_dir)
    _reset_dir(database_dir)
    _reset_dir(projects_dir)
    _reset_dir(temp_dir)

    settings_path = config_dir / "asr_tools_settings.json"
    settings_path.write_text(
        json.dumps({}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    db_path = database_dir / "asr_tools.db"
    _initialize_clean_database(db_path, repo_root)

    print(f"已清理发布目录数据: {release_dir}")
    print(f"- executable: {exe_path}")
    print(f"- settings: {settings_path}")
    print(f"- database: {db_path}")
    print(f"- projects: {projects_dir}")
    print(f"- temp: {temp_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
