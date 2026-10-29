#!/usr/bin/env bash
# Builds build/DeadAir.rbxl with the map baked in, after running the tests.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
echo "== tests"
lune run tests/run.luau
echo "== rojo build"
rojo build default.project.json -o build/DeadAir.rbxl
echo "== bake map"
lune run scripts/bake.luau build/DeadAir.rbxl
echo "Done: build/DeadAir.rbxl"
