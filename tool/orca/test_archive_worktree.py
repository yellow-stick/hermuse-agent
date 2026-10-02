"""Exercise the Linux archive hook with real, isolated processes.

Run with: python3 -m unittest discover -s tool/orca -p 'test_*.py' -v
"""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest


HOOK = Path(__file__).with_name("archive-worktree.sh").resolve()


@unittest.skipUnless(sys.platform == "linux", "archive sweep requires /proc")
class ArchiveWorktreeTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="archive-hook-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "worktree with spaces"
        self.root.mkdir()
        self.outside = self.root.with_name(self.root.name + "-other")
        self.outside.mkdir()

    def run_hook(self, *, fallback=False):
        env = dict(os.environ)
        env.pop("ORCA_WORKTREE_PATH", None)
        if not fallback:
            env["ORCA_WORKTREE_PATH"] = str(self.root)
        return subprocess.run(
            ["bash", str(HOOK)],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )

    def start_process(self, cwd, *, ignore_term=False):
        process = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import signal\n"
                + ("signal.signal(signal.SIGTERM, signal.SIG_IGN)\n" if ignore_term else "")
                + "print('ready', flush=True)\nwhile True: signal.pause()\n",
            ],
            cwd=cwd,
            stdout=subprocess.PIPE,
            text=True,
        )

        def cleanup():
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            process.stdout.close()

        self.addCleanup(cleanup)
        self.assertEqual(process.stdout.readline(), "ready\n")
        return process

    def assert_hook_succeeds(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_empty_worktree_does_not_target_sweep_helpers(self):
        self.assert_hook_succeeds(self.run_hook())

    def test_pwd_fallback_is_resolved_before_leaving_worktree(self):
        self.assert_hook_succeeds(self.run_hook(fallback=True))

    def test_stops_rooted_process_but_preserves_sibling_worktree(self):
        nested = self.root / "build"
        nested.mkdir()
        victim = self.start_process(nested)
        outside = self.start_process(self.outside)
        self.assert_hook_succeeds(self.run_hook())
        self.assertEqual(victim.wait(timeout=5), -signal.SIGTERM)
        self.assertIsNone(outside.poll())

    def test_sigkill_escalation_ignores_unreaped_victim(self):
        victim = self.start_process(self.root, ignore_term=True)
        # Deliberately do not wait/poll until the hook exits: the terminated
        # child remains a zombie and must not block archiving.
        self.assert_hook_succeeds(self.run_hook())
        self.assertEqual(victim.wait(timeout=5), -signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
