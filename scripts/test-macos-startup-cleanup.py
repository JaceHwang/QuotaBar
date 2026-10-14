"""Exercise smoke-test cleanup with real native processes, including orphaned helpers."""
import importlib.util
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location('startup', pathlib.Path(__file__).with_name('test-macos-standalone-startup.py'))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


@unittest.skipUnless(sys.platform == 'darwin', 'Native macOS process fixture')
class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='quotabar-cleanup-test-')
        self.root = pathlib.Path(self.temporary.name).resolve()
        self.app = self.root / 'Fixture.app'
        self.binary = self.app / 'Contents/MacOS/Fixture'
        self.helper = self.app / 'Contents/Helpers/runtime'
        self.binary.parent.mkdir(parents=True)
        self.helper.parent.mkdir(parents=True)
        source = self.root / 'fixture.c'
        source.write_text('''#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "child") == 0) {
        signal(SIGTERM, SIG_IGN); printf("ready\\n"); fflush(stdout); close(1); close(2); for (;;) pause();
    }
    if (argc > 1 && strcmp(argv[1], "exit") == 0) return 0;
    for (;;) pause();
}
''')
        subprocess.run(['xcrun', 'clang', str(source), '-o', str(self.binary)], check=True)
        subprocess.run(['ditto', str(self.binary), str(self.helper)], check=True)
        self.processes = []
        self.children = []

    def tearDown(self):
        for pid in list(startup.owned_processes(self.app)) + self.children:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for process in self.processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=3)
            if process.stdout:
                process.stdout.close()
        self.temporary.cleanup()

    def wait_owned(self):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if startup.owned_processes(self.app):
                return
            time.sleep(.05)
        self.fail('Fixture was not discovered by its exact bundle path')

    def test_app_hanging_before_first_diagnostic_is_stopped(self):
        process = subprocess.Popen([str(self.binary)])
        self.processes.append(process)
        self.wait_owned()
        startup.stop_owned(self.app, grace=.3)
        self.assertEqual(process.wait(timeout=1), -signal.SIGTERM)
        self.assertFalse(startup.owned_processes(self.app))

    def test_long_symlinked_bundle_path_retains_kernel_identity(self):
        directory = self.root / ('long-path-' + 'x' * 150)
        directory.mkdir()
        relocated = directory / 'Fixture.app'
        self.app.rename(relocated)
        alias = self.root / 'alias.app'
        alias.symlink_to(relocated, target_is_directory=True)
        process = subprocess.Popen([str(alias / 'Contents/MacOS/Fixture')])
        self.processes.append(process)
        self.app = alias
        self.wait_owned()
        self.assertIn(process.pid, startup.owned_processes(relocated))
        self.assertEqual(startup.process_snapshot()[process.pid][1], relocated / 'Contents/MacOS/Fixture')
        startup.stop_owned(alias, grace=.3)
        self.assertEqual(process.wait(timeout=1), -signal.SIGTERM)

    def test_helper_is_cleaned_even_when_app_already_exited(self):
        helper = subprocess.Popen([str(self.helper), 'child'], stdout=subprocess.PIPE, text=True)
        self.processes.append(helper)
        self.assertEqual(helper.stdout.readline().strip(), 'ready')
        parent = subprocess.Popen([str(self.binary), 'exit'])
        self.processes.append(parent)
        self.assertEqual(parent.wait(timeout=3), 0)
        self.wait_owned()
        startup.stop_owned(self.app, grace=.3)
        self.assertEqual(helper.wait(timeout=1), -signal.SIGKILL)
        self.assertFalse(startup.owned_processes(self.app))



if __name__ == '__main__':
    unittest.main()
