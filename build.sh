#!/usr/bin/env bash
# 构建 + 测试。用法：./build.sh            构建 bin/odin-gua
#                  ./build.sh test       再跑单元测试与 stdio 冒烟测试
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
odin build src -out:bin/odin-gua -o:speed -vet -strict-style
echo "built bin/odin-gua ($(wc -c < bin/odin-gua) bytes)"
if [[ "${1:-}" == "test" ]]; then
	odin test src/gua -vet -strict-style
	odin test src/journal -vet -strict-style
	python3 tests/smoke.py bin/odin-gua
fi
