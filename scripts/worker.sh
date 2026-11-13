#!/bin/bash
# 워커 실행. 사용: bash scripts/worker.sh <바인딩IP>   (예: TB 링크 IP)
set -euo pipefail; source "$(dirname "$0")/env.sh"
IP=${1:-0.0.0.0}
BUDGET=${VRAM_BUDGET:-14}   # GB. 24GB 맥에서 다른 상주 작업 몫을 남긴다. 모든 구성에서 같은 값을 쓸 것
exec $MMH3 worker --listen $IP:$MMH3_PORT --models $MMH3_MODELS --vram-budget $BUDGET --idle-unload ${IDLE_UNLOAD:-60} 2>&1 | tee -a $BENCH/logs/worker-$(hostname -s)-$(date +%Y%m%d-%H%M%S).log
