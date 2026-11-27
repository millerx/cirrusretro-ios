import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import patch

policy = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/verify-testflight"))
verify_reviews = policy["verify_reviews"]
Rejected = policy["Rejected"]


class ReviewTests(unittest.TestCase):
    sha = "a" * 40
    first = "b" * 40

    def setUp(self):
        self.bot = {"id": policy["CODEX_ID"], "type": "Bot"}
        state = {"code_review": {"commit_sha": self.sha, "status": "completed", "has_unresolved_findings": False}}
        self.comments = [
            {"body": "<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 "
                     + json.dumps(state) + " -->", "user": self.bot}
        ]
        for i, sha in enumerate([self.first, self.sha]):
            self.comments.append({"user": self.bot, "created_at": f"2026-11-27T11:00:0{i}Z",
                                  "html_url": f"https://example.test/{i}",
                                  "body": f"<!-- codex-review-receipt:v1 -->\n**Reviewed commit:** `{sha[:10]}`"})
        self.responses = {"pulls/6/commits": [{"sha": self.first}, {"sha": self.sha}],
                          "pulls/6/reviews": [], "issues/6/comments": self.comments}

    def check(self):
        with patch.dict(verify_reviews.__globals__, items=self.responses.__getitem__):
            verify_reviews(6, self.sha)

    def test_receipts_for_two_distinct_passes(self):
        self.check()
        self.comments.pop(1)
        with self.assertRaises(Rejected):
            self.check()

    def test_old_or_forged_verdict(self):
        self.comments[-1]["user"] = {"id": 123, "type": "Bot"}
        with self.assertRaises(Rejected):
            self.check()
        self.comments[-1]["user"] = self.bot
        self.comments[0]["body"] = self.comments[0]["body"].replace(self.sha, self.first)
        with self.assertRaises(Rejected):
            self.check()

    def test_tag_cannot_substitute_a_different_commit(self):
        verify = policy["verify"]
        with patch.dict(verify.__globals__, api=lambda path: {"object": {"type": "commit", "sha": self.first}}):
            with self.assertRaisesRegex(Rejected, "delivery tag"):
                verify(self.sha, "owner-testflight-6")


if __name__ == "__main__":
    unittest.main()
