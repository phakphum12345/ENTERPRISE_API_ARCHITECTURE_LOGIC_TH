import unittest
from pathlib import Path

from tools.validate_research_os_flutter_live_spine import validate


ROOT = Path(__file__).resolve().parents[1]


class FlutterLiveSpineValidationTests(unittest.TestCase):
    def test_live_spine_validator_passes_after_owner_research_binding_is_normalized(self):
        result = validate(ROOT)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["findings"], [])

    def test_live_spine_result_serializes_source_files_as_repository_paths(self):
        result = validate(ROOT)
        self.assertTrue(result["source_files"])
        self.assertTrue(all(isinstance(path, str) for path in result["source_files"]))
        self.assertTrue(all(not path.startswith("/") for path in result["source_files"]))

    def test_live_spine_contract_keeps_three_explicit_surfaces(self):
        result = validate(ROOT)
        self.assertEqual(
            result["surfaces"],
            {
                "A": "canonical_product_live_surface",
                "B": "privileged_owner_friend_surface",
                "C": "compatibility_release_surface",
            },
        )


if __name__ == "__main__":
    unittest.main()
