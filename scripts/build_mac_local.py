#!/usr/bin/env python3
"""Build the local Mac app with a stable identity so privacy grants survive updates."""
import argparse
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--identity", help="Code-signing certificate SHA-1")
parser.add_argument("--derived-data", default="/private/tmp/today-layout-mac")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
if not (root / "Packages/NativeLogseq/Package.swift").exists():
    parser.error("Initialize Logseq: git submodule update --init --recursive")
identity = args.identity
if not identity:
    result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], check=True, capture_output=True, text=True)
    matches = re.findall(r'\b([0-9A-F]{40}) "Apple Development:', result.stdout)
    if len(matches) != 1:
        parser.error("Specify --identity: exactly one Apple Development certificate is required for automatic selection.")
    identity = matches[0]

# Keep the existing local app's non-sandboxed data location. Distribution builds
# continue to use TodayRoutineMac.entitlements; they need a separate migration plan.
subprocess.run([
    "xcodebuild", "-project", "TodayRoutine.xcodeproj", "-scheme", "TodayRoutineMac",
    "-destination", "platform=macOS", "-derivedDataPath", args.derived_data,
    "build", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=" + identity, "CODE_SIGN_ENTITLEMENTS=",
], cwd=root, check=True)
app = pathlib.Path(args.derived_data) / "Build/Products/Debug/TodayRoutineMac.app"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Signed local app:", app)
