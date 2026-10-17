"""Tests for tools/check_packages.py.
Run: python -m unittest tools.test_check_packages   (or python tools/test_check_packages.py)
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_packages as cp  # noqa: E402


class CheckPackagesTest(unittest.TestCase):
    def conflicts(self, data):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "p.json")
            with open(path, "w", encoding="utf-8-sig") as fh:
                json.dump(data, fh)
            return cp.find_conflicts(cp.load(path)), cp.main([path])

    def test_pair_format_shared(self):
        found, code = self.conflicts([["a", ["x.gd", "y.gd"]], ["b", ["y.gd"]]])
        self.assertEqual(found, [("y.gd", "a", "b")])
        self.assertEqual(code, 1)

    def test_disjoint(self):
        found, code = self.conflicts([["a", ["x.gd"]], {"name": "b", "files": ["y.gd"]}])
        self.assertEqual(found, [])
        self.assertEqual(code, 0)

    def test_transitive_after_resolves(self):
        data = [{"name": "a", "files": ["x"]}, {"name": "b", "files": ["z"], "after": ["a"]},
                {"name": "c", "files": ["x"], "after": ["b"]}]
        self.assertEqual(self.conflicts(data)[0], [])

    def test_unrelated_after_still_conflicts(self):
        data = [{"name": "a", "files": ["x"]}, {"name": "b", "files": ["x"], "after": ["q"]}]
        self.assertEqual(len(self.conflicts(data)[0]), 1)

    def test_waves(self):
        same = [{"name": "a", "files": ["x"], "wave": 1}, {"name": "b", "files": ["x"], "wave": 1}]
        diff = [{"name": "a", "files": ["x"], "wave": 1}, {"name": "b", "files": ["x"], "wave": 2}]
        self.assertEqual(len(self.conflicts(same)[0]), 1)
        self.assertEqual(self.conflicts(diff)[0], [])


if __name__ == "__main__":
    unittest.main()
