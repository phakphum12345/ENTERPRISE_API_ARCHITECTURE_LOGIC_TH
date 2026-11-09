import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "owner_special" / "team_center_contract.json"


def test_owner_service_contract_uses_stable_service_identities():
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    services = contract["owner"]["services"]
    boundaries = contract["service_boundaries"]

    assert services == ["research-os-api", "research-os-v3", "owner-friend"]
    assert set(boundaries) == set(services)
    assert boundaries == {
        "research-os-api": "workspace",
        "research-os-v3": "team-engineering",
        "owner-friend": "friend-internal",
    }
    assert contract["discovery"]["contract"] == "ROS-PORT-DISCOVERY-001"
    assert contract["discovery"]["port_assignment"] == "operating-system"
    assert contract["discovery"]["ollama_endpoint"] == "externally-managed-unchanged"


def test_service_entrypoints_publish_dynamic_service_ids():
    api_launcher = ROOT / "tools" / "research_os_api" / "render_server.py"
    friend_launcher = ROOT / "owner_special" / "scripts" / "run_friend_service.py"
    v3_launcher = ROOT / "v3" / "scripts" / "run_service.py"
    flutter_store = ROOT / "apps" / "research_os_flutter" / "lib" / "src" / "api" / "api_endpoint_store.dart"

    assert '"research-os-api"' in api_launcher.read_text(encoding="utf-8")
    assert '"owner-friend"' in friend_launcher.read_text(encoding="utf-8")
    assert '"research-os-v3"' in v3_launcher.read_text(encoding="utf-8")
    assert "discoverLocalApiEndpoint" in flutter_store.read_text(encoding="utf-8")
