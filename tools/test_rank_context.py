"""Fast checks for shortlist ranking fallback and candidate validation."""

import os
import unittest
from unittest.mock import patch

from tools.rank_context import rank


class RankContextTests(unittest.TestCase):
    def test_keyword_fallback_selects_relevant_candidate(self):
        rows = [{"id": "a", "text": "physics tower collapse"}, {"id": "b", "text": "network lobby"}]
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}):
            result = rank("tower physics", rows)
        self.assertEqual(result["choice"], "a")

    def test_no_match_and_duplicate_ids(self):
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}):
            self.assertEqual(rank("territory", [{"id": "a", "text": "music"}])["choice"], "no_match")
        with self.assertRaises(ValueError):
            rank("x", [{"id": "a", "text": "x"}, {"id": "a", "text": "x"}])


if __name__ == "__main__":
    unittest.main()
