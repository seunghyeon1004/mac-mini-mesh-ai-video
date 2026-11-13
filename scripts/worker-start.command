#!/bin/bash
# 로그인 시 터미널에서 자동 실행되는 워커 감시 루프 (install-persistent.sh가 등록).
# 예산은 ~/mmh3-dist-bench/worker.conf 의 VRAM_BUDGET 을 매번 다시 읽음 → 바꾸고 pkill -f "mmh3 worker" 하면 새 값으로 재시작.
BENCH=$HOME/mmh3-dist-bench
case $(cat ~/.mesh-node 2>/dev/null) in 1) IP=10.77.12.1;; 3) IP=10.77.23.3;; 4) IP=10.77.24.4;; *) echo "워커 맥 아님 (~/.mesh-node 가 1, 3, 4 중 하나여야 함)"; exit 1;; esac
pgrep -f "worker-start.command" | grep -qv "^$$\$" && { echo "이미 감시 루프 실행 중 - 종료"; exit 0; }
printf '\033]0;mmh3 worker (자동)\007'
while :; do
  until ifconfig | grep -q "inet $IP "; do echo "[$(date +%T)] TB IP $IP 대기"; sleep 10; done
  if pgrep -f "mmh3 worker" >/dev/null; then sleep 10; continue; fi   # 다른 창에서 띄운 워커가 있으면 양보
  VRAM_BUDGET=14; [ -f $BENCH/worker.conf ] && source $BENCH/worker.conf
  echo "[$(date +%T)] 워커 시작 (예산 ${VRAM_BUDGET}GB)"
  VRAM_BUDGET=$VRAM_BUDGET bash $BENCH/scripts/worker.sh $IP
  echo "[$(date +%T)] 워커 종료 - 5초 뒤 재시작"; sleep 5
done
