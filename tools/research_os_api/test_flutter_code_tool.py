from __future__ import annotations

import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import flutter_code_tool as tool


class FlutterCodeToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        project = self.root / "apps" / "research_os_flutter"
        project.mkdir(parents=True)
        (project / "lib").mkdir()
        (project / "lib" / "main.dart").write_text("void main() {}\n", encoding="utf-8")
        self.env = patch.dict(os.environ, {
            "RESEARCH_OS_CODE_ROOT": str(self.root),
            "RESEARCH_OS_CODE_OWNER_IDS": "owner@example.com",
            "RESEARCH_OS_FLUTTER_COMMAND": "flutter",
        })
        self.env.start()

    def tearDown(self) -> None:
        self.env.stop()
        self.temp.cleanup()

    def test_project_and_file_read(self) -> None:
        projects = tool.project_map()
        self.assertIn("research_os_flutter", projects)
        payload = tool.read_file("research_os_flutter", "lib/main.dart")
        self.assertEqual(payload["content"], "void main() {}\n")

    def test_rejects_absolute_and_parent_paths(self) -> None:
        with self.assertRaises(ValueError):
            tool.read_file("research_os_flutter", "../secret.dart")
        with self.assertRaises(ValueError):
            tool.read_file("research_os_flutter", "/secret.dart")

    def test_preview_is_sha_bound(self) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        preview = tool.preview("research_os_flutter", "lib/main.dart", current["sha256"], "void main() { print(1); }\n")
        self.assertTrue(preview["changed"])
        self.assertIn("+void main()", preview["diff"])

    @patch("flutter_code_tool.validate", return_value={"ok": True, "steps": []})
    def test_apply_requires_owner_and_validates(self, validate) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        result = tool.apply("research_os_flutter", "lib/main.dart", current["sha256"], "void main() { print(1); }\n", "owner@example.com")
        self.assertTrue(result["applied"])
        validate.assert_called_once()

    def test_non_owner_cannot_apply(self) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        with self.assertRaises(PermissionError):
            tool.apply("research_os_flutter", "lib/main.dart", current["sha256"], "x\n", "dev@example.com")


    def test_owner_id_and_email_allowlists_are_unioned(self) -> None:
        os.environ["RESEARCH_OS_CODE_OWNER_IDS"] = "user:other"
        os.environ["RESEARCH_OS_OWNER_EMAILS"] = "owner@example.com"
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        with patch("flutter_code_tool.validate", return_value={"ok": True, "steps": []}):
            result = tool.apply(
                "research_os_flutter", "lib/main.dart", current["sha256"],
                "void main() { print(2); }\n", "OWNER@example.com",
            )
        self.assertTrue(result["applied"])

    @patch("flutter_code_tool.validate", return_value={"ok": False, "steps": [{"exit_code": 1}]})
    def test_validation_failure_rolls_back_and_records_evidence(self, validate) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        result = tool.apply(
            "research_os_flutter", "lib/main.dart", current["sha256"],
            "void main() { broken( }\n", "owner@example.com",
        )
        self.assertFalse(result["applied"])
        self.assertTrue(result["rolled_back"])
        restored = tool.read_file("research_os_flutter", "lib/main.dart")
        self.assertEqual(restored["sha256"], current["sha256"])
        self.assertTrue(Path(result["evidence"]).is_file())
        validate.assert_called_once()

    def test_apply_rejects_stale_sha(self) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        (self.root / "apps" / "research_os_flutter" / "lib" / "main.dart").write_text(
            "void main() { print(99); }\n", encoding="utf-8"
        )
        with self.assertRaises(RuntimeError):
            tool.apply(
                "research_os_flutter", "lib/main.dart", current["sha256"],
                "void main() { print(3); }\n", "owner@example.com",
            )

    def test_preview_normalizes_newlines_and_reports_matching_hash(self) -> None:
        current = tool.read_file("research_os_flutter", "lib/main.dart")
        crlf_content = "void main() {" + "\r\n" + "  print(1);" + "\r\n" + "}" + "\r\n"
        normalized_content = "void main() {" + "\n" + "  print(1);" + "\n" + "}" + "\n"
        preview = tool.preview(
            "research_os_flutter", "lib/main.dart", current["sha256"], crlf_content,
        )
        self.assertEqual(
            preview["new_sha256"],
            hashlib.sha256(normalized_content.encode("utf-8")).hexdigest(),
        )

if __name__ == "__main__":
    unittest.main()
