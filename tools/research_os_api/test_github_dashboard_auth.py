"""Authorization regression tests for the GitHub dashboard API."""
import os
import unittest
from unittest.mock import patch
from server import ResearchOSHandler

class FakeHandler(ResearchOSHandler):
    def __init__(self, path, headers):
        self.path, self.headers, self.response = path, headers, None
    def _send(self, status, payload):
        self.response = (int(status), payload)

class GitHubDashboardAuthTests(unittest.TestCase):
    def test_requires_session(self):
        h = FakeHandler("/v1/github/dashboard", {})
        with patch("server.require_session", side_effect=ValueError("missing")):
            h.do_GET()
        self.assertEqual(h.response[0], 401)

    def test_requires_owner(self):
        h = FakeHandler("/v1/github/dashboard", {})
        with patch("server.require_session", return_value={"role": "user"}):
            h.do_GET()
        self.assertEqual(h.response[0], 403)

    def test_repository_must_be_allowlisted(self):
        repository = "phakphum12345/ENTERPRISE_API_ARCHITECTURE_LOGIC_TH"
        h = FakeHandler("/v1/github/dashboard?repository=attacker/private", {})
        env = {"RESEARCH_OS_GITHUB_REPOSITORY": repository, "RESEARCH_OS_GITHUB_ALLOWED_REPOSITORIES": repository}
        with patch.dict(os.environ, env), patch("server.require_session", return_value={"role": "owner"}), patch("server.github_dashboard") as dashboard:
            h.do_GET()
        self.assertEqual(h.response[0], 403)
        dashboard.assert_not_called()

    def test_owner_reads_allowed_repository(self):
        repository = "phakphum12345/ENTERPRISE_API_ARCHITECTURE_LOGIC_TH"
        h = FakeHandler("/v1/github/dashboard", {})
        env = {"RESEARCH_OS_GITHUB_REPOSITORY": repository, "RESEARCH_OS_GITHUB_ALLOWED_REPOSITORIES": repository}
        with patch.dict(os.environ, env), patch("server.require_session", return_value={"role": "owner"}), patch("server.github_dashboard", return_value={"repository": repository, "read_only": True}):
            h.do_GET()
        self.assertEqual(h.response[0], 200)

if __name__ == "__main__":
    unittest.main()
