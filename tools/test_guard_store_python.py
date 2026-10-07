import unittest

import guard_store_python as g


class GuardStorePythonTest(unittest.TestCase):
    def test_blocks_store_aliases(self):
        for cmd in ["python3 tools/x.py", "cd /m && python3 -c 'print(1)'", "pip3 install x",
                    "python3.12 -V", "& python3.exe x.py", "C:/Users/t/AppData/Local/Microsoft/WindowsApps/python.exe x",
                    "start ms-windows-store://pdp/?productid=9NQ7512CXL7T", "x | python3"]:
            self.assertTrue(g.blocked(cmd), cmd)

    def test_allows_real_python(self):
        for cmd in ["python tools/x.py", "py -3.13 -V", "python -m pip install x", "git log -- tools/python3_notes.md",
                    "grep -n python3 docs/a.md", "echo mypython3", "",
                    'bd create --title "block python3/pip3" --description "see WindowsApps/python stubs"',
                    'git commit -m "deny python3 (opens ms-windows-store: page)"']:
            self.assertFalse(g.blocked(cmd), cmd)


if __name__ == "__main__":
    unittest.main()
