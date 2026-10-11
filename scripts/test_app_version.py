import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from app_version import read_version, next_version

class AppVersionTests(unittest.TestCase):
    def test_invalid_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'version.json'
            for value in [{'version': 'v1', 'build': 1}, {'version': '1.0', 'build': True}, {'version': '1.0', 'build': 0}, []]:
                path.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    read_version(path)

    def test_build_increment_and_version_order(self):
        self.assertEqual(next_version({'version': '1.9', 'build': 3}, '1.10.0'), {'version': '1.10.0', 'build': 4})
        self.assertEqual(next_version({'version': '1.0', 'build': 3}), {'version': '1.0', 'build': 4})
        with self.assertRaises(ValueError): next_version({'version': '2.0', 'build': 3}, '1.9')
        with self.assertRaises(ValueError): next_version({'version': '1.0', 'build': 3}, build=3)

    def test_generator_uses_metadata_for_every_configuration(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory); (target / 'scripts').mkdir()
            for name in ['app_version.py', 'generate-project.py']:
                (target / 'scripts' / name).write_bytes((root / 'scripts' / name).read_bytes())
            package = target / 'Packages/NativeLogseq'
            package.mkdir(parents=True)
            (package / 'Package.swift').write_bytes((root / 'Packages/NativeLogseq/Package.swift').read_bytes())
            (target / 'app-version.json').write_text('{"version":"2.3.4","build":57}')
            subprocess.run([sys.executable, str(target / 'scripts/generate-project.py')], check=True, capture_output=True)
            result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(target / 'TodayRoutine.xcodeproj/project.pbxproj')], check=True, capture_output=True)
            settings = [obj['buildSettings'] for obj in json.loads(result.stdout)['objects'].values() if obj.get('isa') == 'XCBuildConfiguration' and 'MARKETING_VERSION' in obj.get('buildSettings', {})]
            self.assertEqual(len(settings), 10)
            self.assertTrue(all(s['MARKETING_VERSION'] == '2.3.4' and s['CURRENT_PROJECT_VERSION'] == '57' for s in settings))
            subprocess.run([sys.executable, str(target / 'scripts/app_version.py'), '2.4.0'], check=True, capture_output=True)
            self.assertEqual(json.loads((target / 'app-version.json').read_text()), {'version': '2.4.0', 'build': 58})
            before = (target / 'TodayRoutine.xcodeproj/project.pbxproj').read_bytes()
            rejected = subprocess.run([sys.executable, str(target / 'scripts/app_version.py'), '--build', '1'], capture_output=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual((target / 'TodayRoutine.xcodeproj/project.pbxproj').read_bytes(), before)
            self.assertEqual(json.loads((target / 'app-version.json').read_text())['build'], 58)

if __name__ == '__main__': unittest.main()
