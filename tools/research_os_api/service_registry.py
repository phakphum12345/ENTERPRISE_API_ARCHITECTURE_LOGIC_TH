"""Atomic local endpoint registry for Research OS services.

Each service binds its own socket first (port 0 is supported), then publishes the
actual bound endpoint. The registry is discovery metadata, never an auth or
authorization authority.
"""
from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any

_SCHEMA_VERSION = 1
_SERVICE_RE = re.compile(r"^[a-z][a-z0-9-]{0,63}$")


def registry_directory() -> Path:
    configured = os.environ.get("RESEARCH_OS_SERVICE_REGISTRY_DIR", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    data_dir = (
        os.environ.get("RESEARCH_OS_DATA_DIR", "").strip()
        or os.environ.get("RESEARCH_OS_V3_DATA_DIR", "").strip()
    )
    if data_dir:
        return (Path(data_dir).expanduser() / "run" / "services").resolve()
    if os.name == "nt":
        program_data = os.environ.get("PROGRAMDATA", "").strip()
        if program_data:
            return (Path(program_data) / "ResearchOS" / "run" / "services").resolve()
    return (Path.home() / "ResearchOSData" / "run" / "services").resolve()


def _path(service: str, directory: Path | None = None) -> Path:
    if not _SERVICE_RE.fullmatch(service):
        raise ValueError("invalid service identifier")
    return (directory or registry_directory()) / f"{service}.json"


def publish_endpoint(
    service: str,
    host: str,
    port: int,
    *,
    directory: Path | None = None,
    pid: int | None = None,
) -> dict[str, Any]:
    """Atomically publish an already-bound local HTTP endpoint."""
    if host not in {"127.0.0.1", "::1", "localhost"}:
        raise ValueError("only loopback endpoints may be published")
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError("endpoint port must be an assigned TCP port")
    path = _path(service, directory)
    path.parent.mkdir(parents=True, exist_ok=True)
    authority_host = f"[{host}]" if ":" in host else host
    payload: dict[str, Any] = {
        "schema_version": _SCHEMA_VERSION,
        "service": service,
        "protocol": "http",
        "host": host,
        "port": port,
        "base_url": f"http://{authority_host}:{port}",
        "pid": int(pid if pid is not None else os.getpid()),
    }
    fd, temporary_name = tempfile.mkstemp(prefix=f".{service}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(payload, stream, ensure_ascii=False, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
    return payload


def read_endpoint(service: str, *, directory: Path | None = None) -> dict[str, Any] | None:
    path = _path(service, directory)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    if payload.get("schema_version") != _SCHEMA_VERSION or payload.get("service") != service:
        return None
    host = payload.get("host")
    port = payload.get("port")
    if host not in {"127.0.0.1", "::1", "localhost"}:
        return None
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        return None
    authority_host = f"[{host}]" if ":" in host else host
    expected = f"http://{authority_host}:{port}"
    if payload.get("base_url") != expected or payload.get("protocol") != "http":
        return None
    return payload


def remove_endpoint(
    service: str,
    *,
    directory: Path | None = None,
    pid: int | None = None,
) -> bool:
    """Remove only this service's record, optionally guarded by process identity."""
    path = _path(service, directory)
    current = read_endpoint(service, directory=directory)
    if current is None:
        return False
    if pid is not None and current.get("pid") != pid:
        return False
    try:
        path.unlink()
        return True
    except FileNotFoundError:
        return False


__all__ = ["publish_endpoint", "read_endpoint", "registry_directory", "remove_endpoint"]
