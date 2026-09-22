#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "$0")/../.." && pwd)
test_dir=$(mktemp -d /tmp/coinbase-refresh-test.XXXXXX)
cp "$repo_dir/RefreshProcess.qml" "$test_dir/"
cp "$repo_dir/tests/refresh/shell.qml" "$test_dir/"
output=$(timeout 10 quickshell -p "$test_dir/shell.qml" --no-color 2>&1)
printf '%s\n' "$output"
[[ "$output" == *"PASS: stalled helper terminated, retry completed, failed start cleared"* ]]
