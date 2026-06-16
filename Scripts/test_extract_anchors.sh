#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT=$(swift "$DIR/extract_anchors.swift" "$DIR/fixtures/sample_scene.usda" 2>/tmp/anchors_err.txt || true)
ERR=$(cat /tmp/anchors_err.txt)

fail=0
echo "$OUT" | grep -q "SIMD3<Float>(0.10000, 1.20000, 0.30000)" || { echo "FAIL: 缺 flower 點1"; fail=1; }
echo "$OUT" | grep -q "SIMD3<Float>(0.40000, 1.50000, -0.20000)" || { echo "FAIL: 缺 flower 點2"; fail=1; }
echo "$OUT" | grep -q "SIMD3<Float>(-0.10000, 1.10000, 0.05000)" || { echo "FAIL: 缺 leaf 點1"; fail=1; }
echo "$OUT" | grep -q "9.00000" && { echo "FAIL: 不該收 ignore_me"; fail=1; } || true
echo "$ERR" | grep -q "花 2 點" || { echo "FAIL: 花數量不符 ($ERR)"; fail=1; }
echo "$ERR" | grep -q "葉 1 點" || { echo "FAIL: 葉數量不符 ($ERR)"; fail=1; }
[ "$fail" = "0" ] && echo "ALL TESTS PASSED" || exit 1
