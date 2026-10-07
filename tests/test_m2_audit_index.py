import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import m2_audit_index


class M2AuditIndexTests(unittest.TestCase):
    def test_build_pins_exact_head_sha_and_discovers_required_node_types(self):
        result = m2_audit_index.build()
        self.assertEqual(result["source_sha"], m2_audit_index.run_git("rev-parse", "HEAD"))
        self.assertTrue(result["integrity"]["exact_git_sha"])
        kinds = {node["node_type"] for node in result["nodes"]}
        self.assertTrue({"FILE", "CONTRACT", "TEST", "WORKFLOW", "INVARIANT", "AUTHORITY"} <= kinds)

    def test_build_registers_m2_audit_authority_without_granting_release_authority(self):
        result = m2_audit_index.build()
        gate = next(node for node in result["nodes"] if node["canonical_node_id"] == "AUTHORITY:m2_audit")
        self.assertEqual(gate["status"], "PASS")
        self.assertFalse(result["release_ready"])

    def test_write_outputs_are_machine_readable_and_source_pinned(self):
        result = m2_audit_index.build()
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            m2_audit_index.write_outputs(result, out)
            expected = {
                "m2_audit_index.json",
                "m2_search_trace.json",
                "m2_evidence_graph.json",
                "m2_unresolved.json",
                "m2_final_result.json",
                "m2_audit_index_summary.txt",
            }
            self.assertEqual({p.name for p in out.iterdir()}, expected)
            index = json.loads((out / "m2_audit_index.json").read_text(encoding="utf-8"))
            graph = json.loads((out / "m2_evidence_graph.json").read_text(encoding="utf-8"))
            self.assertEqual(index["source_sha"], result["source_sha"])
            self.assertEqual(graph["source_sha"], result["source_sha"])
            self.assertTrue(all(edge["source_sha"] == result["source_sha"] for edge in graph["edges"]))


if __name__ == "__main__":
    unittest.main()
