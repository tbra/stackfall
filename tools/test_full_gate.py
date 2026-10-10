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

    def test_layer_lint_wired_into_gate(self):
        # The gate runs lint_layers on the candidate tree and any non-green exit makes it RED.
        with open(full_gate.__file__.replace(".pyc", ".py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertIn('run_lint(path, "lint_layers", lint_layers)', src)
        self.assertIn("layer_code == 0", src)
        self.assertIn("layer_lint=%s", src)

    def test_run_lint_uses_candidate_script_and_falls_back(self):
        with tempfile.TemporaryDirectory() as root:
            class Stub(object):
                calls = []

                @staticmethod
                def main(argv):
                    Stub.calls.append(argv)
                    return 7
            self.assertEqual(full_gate.run_lint(root, "lint_layers", Stub), 7)
            os.makedirs(os.path.join(root, "tools"))
            with open(os.path.join(root, "tools", "lint_layers.py"), "w") as fh:
                fh.write("import sys; sys.exit(3)")
            self.assertEqual(full_gate.run_lint(root, "lint_layers", Stub), 3)


if __name__ == "__main__":
    unittest.main()
