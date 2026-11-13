#!/bin/bash
# 이 맥에 고정 커밋으로 mmh3를 받고 빌드한다. 사용: bash scripts/setup.sh
set -euo pipefail; source "$(dirname "$0")/env.sh"
mkdir -p $BENCH/{logs,models}
[ -d $BENCH/src ] || git clone -q https://github.com/niw/mmh3 $BENCH/src
cd $BENCH/src && git fetch -q && git checkout -q $MMH3_COMMIT
test "$(git rev-parse HEAD)" = "$MMH3_COMMIT" || { echo "커밋 불일치"; exit 1; }
make 2>&1 | tail -2 | tee $BENCH/logs/build-$(hostname -s)-${MMH3_COMMIT:0:7}.log
