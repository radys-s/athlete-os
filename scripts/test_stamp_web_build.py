from pathlib import Path
import re
import tempfile
import unittest

from stamp_web_build import ROOT, stamp


class StampTests(unittest.TestCase):
    def test_cache_identity_changes_with_assets_but_not_repeated_stamping(self):
        with tempfile.TemporaryDirectory() as folder:
            build = Path(folder)
            source = (ROOT / "web/service_worker.js").read_text(encoding="utf-8")
            manifest = source.split("const PRECACHE = [", 1)[1].split("];", 1)[0]
            for name in re.findall(r"'([^']+)'", manifest):
                if name == './':
                    continue
                path = build / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture")
            version = stamp(build)
            self.assertEqual(stamp(build), version)
            (build / 'assets/catalog/exercises.json').write_bytes(b"updated catalog")
            self.assertNotEqual(stamp(build), version)

    def test_missing_required_asset_does_not_replace_worker(self):
        with tempfile.TemporaryDirectory() as folder:
            build = Path(folder)
            worker = build / 'service_worker.js'
            worker.write_text('previous worker', encoding='utf-8')
            with self.assertRaisesRegex(RuntimeError, 'Required offline asset missing'):
                stamp(build)
            self.assertEqual(worker.read_text(), 'previous worker')


if __name__ == '__main__':
    unittest.main()
