import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import focus_agent_window as faw  # noqa: E402


def fake_proc(parents):
    root = tempfile.mkdtemp()
    for pid, ppid in parents.items():
        os.makedirs("%s/%d" % (root, pid))
        with open("%s/%d/stat" % (root, pid), "w") as handle:
            handle.write("%d (a (odd) name) S %d 0 0\n" % (pid, ppid))
    return root


class Ancestry(unittest.TestCase):
    def test_walks_up_to_init_nearest_first(self):
        root = fake_proc({40: 30, 30: 20, 20: 1})
        self.assertEqual(faw.ancestry(40, root), [40, 30, 20])

    def test_a_dead_pid_is_only_itself(self):
        self.assertEqual(faw.ancestry(40, fake_proc({})), [40])


class PickWindow(unittest.TestCase):
    def test_the_nearest_ancestor_with_a_window_wins(self):
        clients = [{"pid": 20, "address": "0xa", "title": "bash"},
                   {"pid": 30, "address": "0xb", "title": "kitty"}]
        self.assertEqual(faw.pick_window([40, 30, 20], clients)["address"], "0xb")

    def test_no_ancestor_owns_a_window(self):
        self.assertIsNone(faw.pick_window([40, 30], [{"pid": 99, "address": "0xa"}]))

    def test_a_shared_pid_is_settled_by_the_title(self):
        clients = [{"pid": 30, "address": "0xa", "title": "nvim"},
                   {"pid": 30, "address": "0xb", "title": "* Claude Code"}]
        self.assertEqual(faw.pick_window([40, 30], clients, hints=["claude"])["address"], "0xb")

    def test_a_shared_pid_with_no_matching_title_takes_the_first(self):
        clients = [{"pid": 30, "address": "0xa", "title": "nvim"},
                   {"pid": 30, "address": "0xb", "title": "htop"}]
        self.assertEqual(faw.pick_window([40, 30], clients, hints=["claude"])["address"], "0xa")


if __name__ == "__main__":
    unittest.main()
