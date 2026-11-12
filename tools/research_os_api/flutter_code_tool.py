from __future__ import annotations

"""Owner-only local Flutter code editing service.

Reads are restricted to allowlisted project roots and source-text extensions.
Writes are SHA-bound, atomically replaced, validated with Flutter, rolled back
when validation fails, and recorded as audit evidence.
"""

import hashlib
import json
import os
import shlex
import subprocess
import tempfile
import threading
import time
from difflib import unified_diff
from pathlib import Path
from typing import Any

MAX_FILE_BYTES = 1024 * 1024
MAX_LIST_ITEMS = 2000
BLOCKED_PARTS = {".git", ".dart_tool", "build", "__pycache__"}
BLOCKED_PREFIXES = (".github/workflows/",)
TEXT_EXTENSIONS = {
    ".dart", ".yaml", ".yml", ".json", ".md", ".txt", ".py", ".toml",
    ".xml", ".gradle", ".properties", ".html", ".css", ".js", ".ts",
}

# Serializes edits made through this process. The SHA is still rechecked just
# before replacement because other processes may modify the file independently.
_WRITE_LOCK = threading.RLock()


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _normalize_newlines(content: str) -> str:
    return content.replace("\r\n", "\n").replace("\r", "\n")


def _projects(root: Path) -> dict[str, Path]:
    configured = (os.environ.get("RESEARCH_OS_CODE_PROJECTS") or "").strip()
    result: dict[str, Path] = {}
    if configured:
        for item in configured.split(","):
            if "=" not in item:
                continue
            name, relative = item.split("=", 1)
            name, relative = name.strip(), relative.strip()
            if name and relative:
                result[name] = (root / relative).resolve()
    if not result:
        result["research_os_flutter"] = (root / "apps" / "research_os_flutter").resolve()
    return result


def _root() -> Path:
    configured = (os.environ.get("RESEARCH_OS_CODE_ROOT") or "").strip()
    return Path(configured).resolve() if configured else Path(__file__).resolve().parents[2]


def project_map() -> dict[str, str]:
    root = _root()
    result: dict[str, str] = {}
    for name, path in _projects(root).items():
        if not path.is_dir():
            continue
        try:
            result[name] = path.relative_to(root).as_posix()
        except ValueError:
            # Never expose or accept a configured project outside the code root.
            continue
    return result


def _project(name: str) -> tuple[Path, Path]:
    root = _root()
    projects = _projects(root)
    if name not in projects:
        raise ValueError("unknown code project")
    project = projects[name]
    try:
        project.relative_to(root)
    except ValueError as exc:
        raise ValueError("code project escapes code root") from exc
    if not project.is_dir():
        raise ValueError("code project is not available")
    return root, project


def _safe_path(project: Path, relative: str) -> Path:
    value = relative.replace("\\", "/").strip()
    parts = value.split("/")
    if not value or value.startswith("/") or ":" in parts[0] or any(p in {"", ".", ".."} for p in parts):
        raise ValueError("invalid or absolute paths are not allowed")
    candidate = (project / value).resolve()
    try:
        candidate.relative_to(project)
    except ValueError as exc:
        raise ValueError("path escapes project root") from exc
    rel = candidate.relative_to(project).as_posix()
    if any(part in BLOCKED_PARTS for part in candidate.relative_to(project).parts):
        raise ValueError("path is protected")
    if any(rel.startswith(prefix) for prefix in BLOCKED_PREFIXES):
        raise ValueError("workflow files are protected")
    if candidate.suffix.lower() not in TEXT_EXTENSIONS:
        raise ValueError("unsupported source file type")
    return candidate


def list_files(project_name: str, query: str = "") -> dict[str, Any]:
    _, project = _project(project_name)
    query = query.strip().casefold()
    items: list[dict[str, Any]] = []
    for path in project.rglob("*"):
        if len(items) >= MAX_LIST_ITEMS:
            break
        try:
            if not path.is_file():
                continue
            rel = path.relative_to(project)
            safe = _safe_path(project, rel.as_posix())
            size = safe.stat().st_size
        except (ValueError, OSError):
            continue
        if query and query not in rel.as_posix().casefold():
            continue
        items.append({"path": rel.as_posix(), "bytes": size})
    items.sort(key=lambda item: item["path"])
    return {"project": project_name, "items": items, "count": len(items)}


def read_file(project_name: str, relative: str) -> dict[str, Any]:
    _, project = _project(project_name)
    path = _safe_path(project, relative)
    data = path.read_bytes()
    if len(data) > MAX_FILE_BYTES:
        raise ValueError("file is too large")
    content = _normalize_newlines(data.decode("utf-8"))
    return {
        "project": project_name,
        "path": path.relative_to(project).as_posix(),
        "content": content,
        # Bind concurrency checks to exact on-disk bytes, not normalized text.
        "sha256": _sha_bytes(data),
        "bytes": len(data),
    }


def preview(project_name: str, relative: str, original_sha256: str, content: str) -> dict[str, Any]:
    current = read_file(project_name, relative)
    if current["sha256"] != original_sha256:
        raise RuntimeError("file changed since it was read; refresh before preview")
    if len(content.encode("utf-8")) > MAX_FILE_BYTES:
        raise ValueError("file is too large")
    before = current["content"].splitlines(keepends=True)
    after = _normalize_newlines(content).splitlines(keepends=True)
    diff = "".join(unified_diff(
        before, after,
        fromfile=f"a/{current['path']}",
        tofile=f"b/{current['path']}",
    ))
    return {
        "project": project_name,
        "path": current["path"],
        "original_sha256": original_sha256,
        "new_sha256": _sha(_normalize_newlines(content)),
        "changed": _normalize_newlines(content) != current["content"],
        "diff": diff,
    }


def _run(command: list[str], cwd: Path, timeout: int) -> dict[str, Any]:
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "command": command,
            "exit_code": completed.returncode,
            "stdout": completed.stdout[-12000:],
            "stderr": completed.stderr[-12000:],
            "duration_seconds": round(time.monotonic() - started, 3),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": command,
            "exit_code": 124,
            "stdout": (exc.stdout or "")[-12000:] if isinstance(exc.stdout, str) else "",
            "stderr": ((exc.stderr or "")[-12000:] if isinstance(exc.stderr, str) else "")
            + f"\nCommand timed out after {timeout} seconds.",
            "duration_seconds": round(time.monotonic() - started, 3),
        }
    except OSError as exc:
        return {
            "command": command,
            "exit_code": 127,
            "stdout": "",
            "stderr": f"Unable to start command: {exc}",
            "duration_seconds": round(time.monotonic() - started, 3),
        }


def validate(project_name: str) -> dict[str, Any]:
    _, project = _project(project_name)
    configured = (os.environ.get("RESEARCH_OS_FLUTTER_COMMAND") or "flutter").strip()
    try:
        flutter_command = shlex.split(configured, posix=(os.name != "nt"))
    except ValueError as exc:
        return {"ok": False, "steps": [{
            "command": configured, "exit_code": 127, "stdout": "",
            "stderr": f"Invalid Flutter command configuration: {exc}",
            "duration_seconds": 0,
        }]}
    if not flutter_command:
        return {"ok": False, "steps": [{
            "command": configured, "exit_code": 127, "stdout": "",
            "stderr": "Flutter command is empty.", "duration_seconds": 0,
        }]}
    analyze = _run([*flutter_command, "analyze"], project, 300)
    if analyze["exit_code"] != 0:
        return {"ok": False, "steps": [analyze]}
    test = _run([*flutter_command, "test"], project, 600)
    return {"ok": test["exit_code"] == 0, "steps": [analyze, test]}


def _atomic_write(path: Path, data: bytes) -> None:
    """Write bytes to a same-directory temporary file and atomically replace."""
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", suffix=".tmp",
            dir=path.parent, delete=False,
        ) as handle:
            temp_path = Path(handle.name)
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if path.exists():
            try:
                os.chmod(temp_path, path.stat().st_mode)
            except OSError:
                pass
        os.replace(temp_path, path)
    finally:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass


def _owner_allowlist() -> set[str]:
    # IDs and email addresses are both valid configured identities.
    settings = (
        os.environ.get("RESEARCH_OS_CODE_OWNER_IDS", ""),
        os.environ.get("RESEARCH_OS_OWNER_EMAILS", ""),
    )
    return {
        item.strip().casefold()
        for setting in settings
        for item in setting.split(",")
        if item.strip()
    }


def _write_evidence(evidence_dir: Path, evidence: dict[str, Any]) -> Path:
    evidence_dir.mkdir(parents=True, exist_ok=True)
    path = evidence_dir / f"{int(time.time() * 1000)}-{threading.get_ident()}.json"
    _atomic_write(
        path,
        (json.dumps(evidence, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
    )
    return path


def apply(
    project_name: str,
    relative: str,
    original_sha256: str,
    content: str,
    principal: str,
) -> dict[str, Any]:
    principal_key = principal.strip().casefold()
    allowed = _owner_allowlist()
    if not allowed or not principal_key or principal_key not in allowed:
        raise PermissionError("OWNER authority is required for code changes")
    if len(content.encode("utf-8")) > MAX_FILE_BYTES:
        raise ValueError("file is too large")

    root, project = _project(project_name)
    path = _safe_path(project, relative)
    evidence_dir = root / "evidence" / "flutter-code-tool"

    with _WRITE_LOCK:
        current = read_file(project_name, relative)
        if current["sha256"] != original_sha256:
            raise RuntimeError("file changed since it was read; refresh before apply")
        old_bytes = path.read_bytes()
        if _sha_bytes(old_bytes) != original_sha256:
            raise RuntimeError("file changed since it was read; refresh before apply")
        old_content = _normalize_newlines(old_bytes.decode("utf-8"))
        new_content = _normalize_newlines(content)
        if old_content == new_content:
            return {
                "applied": False,
                "rolled_back": False,
                "validation": {"ok": True, "steps": []},
                "sha256": original_sha256,
            }

        # Ensure the audit destination is available before mutating source.
        evidence_dir.mkdir(parents=True, exist_ok=True)
        _atomic_write(path, new_content.encode("utf-8"))

        try:
            validation = validate(project_name)
        except Exception as exc:  # convert tool failures into a failed validation
            validation = {
                "ok": False,
                "steps": [{
                    "command": ["validate"],
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": f"Validation raised {type(exc).__name__}: {exc}",
                    "duration_seconds": 0,
                }],
            }

        rolled_back = not validation.get("ok", False)
        if rolled_back:
            # Do not overwrite a third-party edit made while validation ran.
            if _sha_bytes(path.read_bytes()) == _sha_bytes(new_content.encode("utf-8")):
                _atomic_write(path, old_bytes)
            else:
                raise RuntimeError(
                    "validation failed, but the file changed concurrently; "
                    "automatic rollback was refused to avoid overwriting that change"
                )

        final_bytes = path.read_bytes()
        evidence = {
            "tool": "owner-flutter-code-tool",
            "principal": principal,
            "project": project_name,
            "path": current["path"],
            "before_sha256": original_sha256,
            "attempted_sha256": _sha_bytes(new_content.encode("utf-8")),
            "validation": validation,
            "rolled_back": rolled_back,
            "final_sha256": _sha_bytes(final_bytes),
            "timestamp": time.time(),
        }
        evidence_path = _write_evidence(evidence_dir, evidence)
        return {
            "applied": not rolled_back,
            "rolled_back": rolled_back,
            "evidence": str(evidence_path),
            "validation": validation,
            "sha256": evidence["final_sha256"],
        }
