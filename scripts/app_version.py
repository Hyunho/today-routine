"""Shared app version metadata and explicit version update command."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / 'app-version.json'


def validate_version(value):
    if not isinstance(value, dict):
        raise ValueError('버전 파일은 JSON 객체여야 합니다.')
    version = value.get('version')
    build = value.get('build')
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?', version):
        raise ValueError('버전은 1.0 또는 1.1.0 형식이어야 합니다.')
    if type(build) is not int or not 1 <= build <= 999999999:
        raise ValueError('빌드 번호는 1~999999999 사이 정수여야 합니다.')
    return {'version': version, 'build': build}


def read_version(path=VERSION_FILE):
    return validate_version(json.loads(Path(path).read_text(encoding='utf-8')))


def next_version(current, version=None, build=None):
    target = validate_version({'version': version or current['version'], 'build': current['build'] + 1 if build is None else build})
    def parts(text):
        values = tuple(map(int, text.split('.')))
        return values + (0,) * (3 - len(values))
    if parts(target['version']) < parts(current['version']):
        raise ValueError('앱 버전은 이전 버전보다 낮출 수 없습니다.')
    if target['build'] <= current['build']:
        raise ValueError('빌드 번호는 이전 번호보다 커야 합니다.')
    return target


def main():
    parser = argparse.ArgumentParser(description='앱 버전 확인·변경 및 Xcode 프로젝트 갱신')
    parser.add_argument('version', nargs='?', help='새 버전 (예: 1.1.0). 빌드 번호는 기본적으로 1 증가합니다.')
    parser.add_argument('--build', type=int, help='명시적인 새 빌드 번호')
    parser.add_argument('--bump-build', action='store_true', help='앱 버전은 유지하고 빌드 번호만 증가')
    args = parser.parse_args()
    try:
        current = read_version()
        if args.version is None and args.build is None and not args.bump_build:
            print(f"{current['version']} ({current['build']})")
            return
        target = next_version(current, args.version, args.build)
        original = VERSION_FILE.read_bytes()
        try:
            VERSION_FILE.write_text(json.dumps(target, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            subprocess.run([sys.executable, str(ROOT / 'scripts/generate-project.py')], check=True)
        except Exception:
            VERSION_FILE.write_bytes(original)
            raise
        print(f"{current['version']} ({current['build']}) → {target['version']} ({target['build']})")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'버전을 변경하지 못했습니다: {error}\n')


if __name__ == '__main__':
    main()
