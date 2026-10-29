#!/usr/bin/env bash
# Builds build/DeadAir.rbxl with the map baked in, after running the tests.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
echo "== tests"
lune run tests/run.luau
if command -v python3 >/dev/null && command -v ffmpeg >/dev/null && python3 -c "import numpy" 2>/dev/null; then
	echo "== audio banks"
	python3 scripts/audio/check_banks.py
else
	echo "== audio banks (skipped: needs python3, numpy and ffmpeg)"
fi
echo "== rojo build"
rojo build default.project.json -o build/DeadAir.rbxl
echo "== bake map"
lune run scripts/bake.luau build/DeadAir.rbxl
echo "Done: build/DeadAir.rbxl"
