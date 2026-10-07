#!/usr/bin/env python3
"""Fail-closed static validator for the Research OS Flutter live topology."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "current" / "RESEARCH_OS_FLUTTER_LIVE_SPINE_CONTRACT.json"

A_ENDPOINT = ROOT / "apps/research_os_flutter/lib/src/api/api_endpoint_store.dart"
A_APP = ROOT / "apps/research_os_flutter/lib/src/research_os_app.dart"
B_MAIN = ROOT / "owner_special/flutter_app/lib/main.dart"
B_API = ROOT / "owner_special/flutter_app/lib/src/owner_api.dart"
C_MAIN = ROOT / "v3/flutter_app/lib/main.dart"
C_API = ROOT / "v3/flutter_app/lib/src/api/v3_api.dart"

CANONICAL_RENDER = "https://research-os-api-phakphoum.onrender.com"
LOOPBACK_RESEARCH = "http://127.0.0.1:8787"
LOOPBACK_OWNER = "http://127.0.0.1:8790"
LOOPBACK_V3 = "http://127.0.0.1:8788"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def has(text: str, fragment: str) -> bool:
    return fragment in text


def validate(root: Path = ROOT) -> dict[str, object]:
    findings: list[dict[str, str]] = []

    contract = json.loads(read(root / "current/RESEARCH_OS_FLUTTER_LIVE_SPINE_CONTRACT.json"))

    a_endpoint = read(root / "apps/research_os_flutter/lib/src/api/api_endpoint_store.dart")
    a_app = read(root / "apps/research_os_flutter/lib/src/research_os_app.dart")
    b_main = read(root / "owner_special/flutter_app/lib/main.dart")
    b_api = read(root / "owner_special/flutter_app/lib/src/owner_api.dart")
    c_main = read(root / "v3/flutter_app/lib/main.dart")
    c_api = read(root / "v3/flutter_app/lib/src/api/v3_api.dart")

    required_paths = {
        "A_endpoint": root / "apps/research_os_flutter/lib/src/api/api_endpoint_store.dart",
        "A_entrypoint": root / "apps/research_os_flutter/lib/src/research_os_app.dart",
        "B_entrypoint": root / "owner_special/flutter_app/lib/main.dart",
        "B_api": root / "owner_special/flutter_app/lib/src/owner_api.dart",
        "C_entrypoint": root / "v3/flutter_app/lib/main.dart",
        "C_api": root / "v3/flutter_app/lib/src/api/v3_api.dart",
    }
    required_content = {
        "A_endpoint": a_endpoint,
        "A_entrypoint": a_app,
        "B_entrypoint": b_main,
        "B_api": b_api,
        "C_entrypoint": c_main,
        "C_api": c_api,
    }
    for name, content in required_content.items():
        if not content:
            findings.append({"surface": name, "state": "UNKNOWN", "reason": "required source file missing"})

    if a_endpoint:
        if not has(a_endpoint, CANONICAL_RENDER):
            findings.append({"surface": "A", "state": "DRIFT", "reason": "canonical Render endpoint missing"})
        if not has(a_endpoint, "RESEARCH_OS_API_BASE_URL"):
            findings.append({"surface": "A", "state": "DRIFT", "reason": "production API environment binding missing"})
        if not has(a_app, "ResearchOSApiClient(baseUrl: url)"):
            findings.append({"surface": "A", "state": "DRIFT", "reason": "A entrypoint does not consume ApiEndpointStore"})

    if b_main and b_api:
        if not has(b_main, "RESEARCH_OS_FRIEND_URL"):
            findings.append({"surface": "B", "state": "DRIFT", "reason": "Owner/Friend service environment binding missing"})
        if not has(b_api, "RESEARCH_OS_API_BASE_URL"):
            findings.append({"surface": "B", "state": "DRIFT", "reason": "Research API production environment binding missing"})
        if has(b_api, f"researchOsBaseUrl = '{LOOPBACK_RESEARCH}'"):
            findings.append({
                "surface": "B",
                "state": "DRIFT",
                "reason": "Research API is hard-coded to loopback; production must bind to canonical Render",
            })
        if not has(b_api, "/v1/auth/status") or not has(b_api, "/v1/ai/generate"):
            findings.append({"surface": "B", "state": "UNKNOWN", "reason": "Research auth/chat paths are not provable"})

    if c_main and c_api:
        if not has(c_main, "RESEARCH_OS_V3_BASE_URL"):
            findings.append({"surface": "C", "state": "DRIFT", "reason": "V3 runtime environment binding missing"})
        if not has(c_main, LOOPBACK_V3):
            findings.append({"surface": "C", "state": "DRIFT", "reason": "V3 compatibility loopback default is not explicit"})
        if not has(c_api, "/v3/providers") or not has(c_api, "/v3/master"):
            findings.append({"surface": "C", "state": "UNKNOWN", "reason": "V3 compatibility API paths are not provable"})

    # Reject accidental hard-coded production-looking endpoint changes outside A's store.
    for surface, text in (("B", b_api), ("C", c_main + c_api)):
        if CANONICAL_RENDER in text and surface == "C":
            findings.append({"surface": surface, "state": "DRIFT", "reason": "V3 compatibility surface must not become the public product authority"})

    status = "PASS" if not findings else "FAIL"
    return {
        "contract_id": contract.get("contract_id"),
        "status": status,
        "source_files": sorted(str(path.relative_to(root)) for path in required_paths.values()),
        "canonical_render": CANONICAL_RENDER,
        "surfaces": {
            "A": "canonical_product_live_surface",
            "B": "privileged_owner_friend_surface",
            "C": "compatibility_release_surface",
        },
        "findings": findings,
        "summary": {
            "finding_count": len(findings),
            "unknown_is_not_pass": True,
            "auto_repair": "delegated; endpoint/auth authority changes are not auto-repaired",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    result = validate(args.root.resolve())
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(payload, end="")
    if args.json_out:
        args.json_out.write_text(payload, encoding="utf-8")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
