from pathlib import Path

from tools.validate_research_os_flutter_live_spine import validate


ROOT = Path(__file__).resolve().parents[1]


def test_live_spine_validator_passes_after_owner_research_binding_is_normalized():
    result = validate(ROOT)
    assert result["status"] == "PASS"
    assert result["findings"] == []


def test_live_spine_contract_keeps_three_explicit_surfaces():
    result = validate(ROOT)
    assert result["surfaces"] == {
        "A": "canonical_product_live_surface",
        "B": "privileged_owner_friend_surface",
        "C": "compatibility_release_surface",
    }
