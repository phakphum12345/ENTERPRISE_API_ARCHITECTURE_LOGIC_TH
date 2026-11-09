from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Bootstrap the packaged Owner Special source root deterministically. This mirrors
# the certified V3 service entrypoint and does not depend on PYTHONPATH being
# honored by a relocated/bundled Python runtime or by the Windows SCM process.
OWNER_SPECIAL_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = OWNER_SPECIAL_ROOT.parent
for source_root in (OWNER_SPECIAL_ROOT, REPOSITORY_ROOT):
    if str(source_root) not in sys.path:
        sys.path.insert(0, str(source_root))

from research_os_friend import OwnerFriendService
from tools.research_os_api.service_registry import (
    publish_endpoint,
    registry_directory,
    remove_endpoint,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Research OS Owner Special Friend Service")
    parser.add_argument("--owner-id", default="owner")
    parser.add_argument("--host", default="127.0.0.1")
    # Port 0 delegates allocation and bind atomically to the operating system.
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--data-root", type=Path, default=None)
    parser.add_argument("--audit-path", type=Path, default=None)
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    parser.add_argument("--registry-dir", type=Path, default=None)
    args = parser.parse_args()

    service = OwnerFriendService(
        owner_id=args.owner_id,
        host=args.host,
        port=args.port,
        data_root=args.data_root,
        audit_path=args.audit_path,
        repository_root=args.repository_root,
    )
    registry_dir = args.registry_dir or registry_directory()
    published = False
    try:
        endpoint = publish_endpoint(
            "owner-friend",
            service.host,
            service.port,
            directory=registry_dir,
        )
        published = True
        print(
            f"Owner Friend Service READY {endpoint['base_url']} registry={registry_dir}",
            flush=True,
        )
        service.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if published:
            remove_endpoint(
                "owner-friend",
                directory=registry_dir,
                pid=os.getpid(),
            )
        service.close()


if __name__ == "__main__":
    main()
