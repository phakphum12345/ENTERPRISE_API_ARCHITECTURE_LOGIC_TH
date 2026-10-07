from pathlib import Path

from tools.validate_research_os_flutter_live_spine import validate


ROOT = Path(__file__).resolve().parents[1]


def test_live_spine_validator_is_fail_closed_against_current_owner_binding():
    result = validate(ROOT)
    assert result["status"] == "FAIL"
    findings = result["findings"]
    assert any(
        item["surface"] == "B"
        and "Research API production environment binding" in item["reason"]
        for item in findings
    )


def test_live_spine_contract_keeps_three_explicit_surfaces():
    result = validate(ROOT)
    assert result["surfaces"] == {
        "A": "canonical_product_live_surface",
        "B": "privileged_owner_friend_surface",
        "C": "compatibility_release_surface",
    }
