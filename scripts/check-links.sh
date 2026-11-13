#!/bin/bash
# 연결 점검: 이 맥에서 각 워커로 ping + mmh3 probe(스텝 교환량 시뮬레이션 포함)
# 사용: bash scripts/check-links.sh 10.12.0.3 10.13.0.3 ...
# 워커끼리 점검은 각 워커 맥에서 이 스크립트를 다른 워커 IP로 실행한다.
set -uo pipefail; source "$(dirname "$0")/env.sh"
TS=$(date +%Y%m%d-%H%M%S); OUT=$BENCH/logs/links-$(hostname -s)-$TS.log
for H in "$@"; do
  { echo "=== $(hostname -s) -> $H  ($TS)"
    route -n get $H 2>/dev/null | grep -E 'interface|gateway'
    ping -c5 -q $H | tail -1
    $MMH3 worker --probe $H 2>&1; } | tee -a $OUT
done
