"""Unit tests for the shard/serial split in full_gate.py (no Godot launched)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import full_gate  # noqa: E402


class SerialSplitTest(unittest.TestCase):
    def write(self, text):
        fd, p = tempfile.mkstemp(suffix=".txt")
        os.close(fd)
        self.addCleanup(os.remove, p)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        return p

    def test_list_filters_unknown_comments_and_dupes(self):
        p = self.write("# c\nres://a.gd  # trailing\n\nres://gone.gd\nres://a.gd\nres://b.gd\n")
        self.assertEqual(full_gate.load_serial_list(p, ["res://a.gd", "res://b.gd", "res://c.gd"]),
                         ["res://a.gd", "res://b.gd"])

    def test_missing_file_is_empty(self):
        self.assertEqual(full_gate.load_serial_list("/nonexistent/x.txt", ["res://a.gd"]), [])

    def test_shards_exclude_serial_scripts(self):
        tests = ["res://t%d.gd" % i for i in range(6)]
        serial = ["res://t0.gd", "res://t3.gd"]
        shards = full_gate.make_shards(".", [t for t in tests if t not in serial], 2, {})
        flat = [t for s in shards for t in s]
        self.assertEqual(sorted(flat), sorted(set(tests) - set(serial)))

    def test_seed_list_entries_exist(self):
        tests = full_gate.collect(full_gate.ROOT)
        with open(full_gate.SERIAL_LIST, encoding="utf-8") as fh:
            wanted = [l.split("#")[0].strip() for l in fh if l.split("#")[0].strip()]
        self.assertEqual([w for w in wanted if w not in tests], [])


if __name__ == "__main__":
    unittest.main()
