from __future__ import annotations

import json
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = PROJECT_ROOT.parent
for source_root in (PROJECT_ROOT, REPOSITORY_ROOT):
    if str(source_root) not in sys.path:
        sys.path.insert(0, str(source_root))

from research_os_v3 import DataLayout, UnifiedMasterOrchestrator, V3LocalService
from research_os_v3.models import SCALE_PROFILES
from tools.research_os_api.service_registry import (
    publish_endpoint,
    registry_directory,
    remove_endpoint,
)


def main() -> int:
    host = os.environ.get("RESEARCH_OS_V3_HOST", "127.0.0.1")
    port = int(os.environ.get("RESEARCH_OS_V3_PORT", "0"))
    layout = DataLayout.from_environment().ensure()
    audit_path = layout.logs / "http-audit.jsonl"
    maximum = SCALE_PROFILES[-1]
    service = V3LocalService(host=host, port=port, audit_path=audit_path)
    server = service.build_server()
    actual_host, actual_port = server.server_address[:2]
    configured_registry = os.environ.get("RESEARCH_OS_SERVICE_REGISTRY_DIR", "").strip()
    registry_dir = (
        Path(configured_registry).expanduser().resolve()
        if configured_registry
        else layout.root / "run" / "services"
    )
    published = False
    if actual_host in {"127.0.0.1", "::1", "localhost"}:
        endpoint = publish_endpoint(
            "research-os-v3",
            str(actual_host),
            int(actual_port),
            directory=registry_dir,
        )
        published = True
    print(
        json.dumps(
            {
                "service": "research-os-v3-full-10x10",
                "host": str(actual_host),
                "port": int(actual_port),
                "base_url": endpoint["base_url"] if published else None,
                "contract": UnifiedMasterOrchestrator.contract,
                "maximum_scale": maximum.tier.value,
                "maximum_logical_capacity": maximum.capacity,
                "capacity_policy": "lazy-bounded-execution",
                "data_root": str(layout.root),
                "http_audit": str(audit_path),
            },
            sort_keys=True,
        ),
        flush=True,
    )
    try:
        service.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        service.shutdown()
        if published:
            remove_endpoint("research-os-v3", directory=registry_dir, pid=os.getpid())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
