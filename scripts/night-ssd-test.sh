#!/bin/bash
# 야간 A/B: 워커 메모리 상한 14GB(지금) vs 6GB(거의 전부 SSD 스트리밍)
# 같은 프롬프트·시드·해상도로 5초 클립 1개씩 → 시간·스왑아웃·상주 블록 수 비교 → 더 나은 쪽으로 워커를 남겨 둠.
# Mac2 Terminal에서 실행해야 함(로컬 네트워크 권한). 00:30까지 기다렸다 시작.
set -uo pipefail; source "$(dirname "$0")/env.sh"
OUT=$BENCH/results/ssd-test-$(date +%Y%m%d).md; LOG=$BENCH/logs/night-ssd-$(date +%Y%m%d-%H%M%S).log
log(){ echo "[$(date +%T)] $*" | tee -a $LOG; }
M3="mac3"
HOSTS=("mac1|10.77.12.1|mmh3-n1" "$M3|10.77.23.3|mmh3-n3" "mac4|10.77.24.4|mmh3-n4")

until (( 10#$(date +%H%M) >= 30 && 10#$(date +%H%M) < 450 )); do sleep 60; done
log "시작"

restart_workers(){  # $1 = 예산 GB
  for h in "${HOSTS[@]}"; do IFS='|' read -r ssh ip name <<< "$h"
    # 자동 감시 루프가 있으면 worker.conf만 바꾸고 pkill(루프가 새 예산으로 재시작), 없으면 터미널로 직접 띄움
    ssh -n -o ConnectTimeout=5 $ssh "echo VRAM_BUDGET=$1 > ~/mmh3-dist-bench/worker.conf; pkill -f 'mmh3 worker'; sleep 2; pgrep -f worker-start.command >/dev/null || osascript -e 'tell application \"Terminal\" to do script \"VRAM_BUDGET=$1 bash ~/mmh3-dist-bench/scripts/worker.sh $ip\"' >/dev/null"
    sleep 8
    for i in $(seq 1 30); do nc -z -G 2 $name 7833 2>/dev/null && break; sleep 2; done
    nc -z -G 2 $name 7833 || { log "$name 워커 안 뜸 - 중단"; exit 1; }
  done; log "워커 3대 예산 ${1}GB로 재시작"; sleep 30
}
swapsum(){ bash $BENCH/scripts/swapmon.sh | awk '{printf "%s:%s ",$1,$2}'; }
keeping(){  # 워커별 최근 로그의 상주 블록 수
  for h in "${HOSTS[@]}"; do IFS='|' read -r ssh ip name <<< "$h"
    ssh -n -o ConnectTimeout=5 $ssh 'grep -h "DiT blocks" $(ls -t ~/mmh3-dist-bench/logs/worker-*.log | head -1) | tail -1' | sed "s/^/$name: /"; done
}

echo "# 워커 메모리 상한 A/B ($(date +%F))" > $OUT
for B in 14 6; do
  restart_workers $B
  S0=$(bash $BENCH/scripts/swapmon.sh)
  VRAM_BUDGET=8 SEED=7 W=672 H=384 FRAMES=121 STEPS=4 $(command -v timeout || command -v gtimeout) 1500 bash $BENCH/scripts/bench.sh ssd-b$B \
    --patch minimax_h3_fasth3_vsa_datafree_patch_rank64.safetensors \
    --worker mmh3-n1 --worker-units steps --worker mmh3-n3 --worker-units steps --worker mmh3-n4 --worker-units steps < /dev/null >> $LOG 2>&1
  S1=$(bash $BENCH/scripts/swapmon.sh)
  BL=$(ls -t $BENCH/logs/bench-ssd-b$B-*.log | head -1)
  w=$(grep -oE "wall_to_mp4=[0-9.]+" $BL | cut -d= -f2); w=${w:-9999}; eval "WALL$B=$w"
  D=$(paste -d' ' <(echo "$S0") <(echo "$S1") | awk '{d=($5-$2)*16/1024; t+=d; printf "%s:+%dMB ",$1,d} END{printf "|%d",t}')
  eval "SW$B=${D##*|}"
  { echo; echo "## 예산 ${B}GB"; echo "- MP4까지: ${w}s"; echo "- 스왑아웃: ${D%|*}"
    echo "- 스텝: $(grep -E '^step [0-9]/4' $BL | awk '{print $(NF-1)"s"}' | tr '\n' ' ')"
    echo '```'; keeping; grep -h "step 3 of rank" $BL 2>/dev/null; echo '```'; } >> $OUT
  log "예산 ${B}GB: ${w}s, 스왑아웃 합 ${D##*|}MB"
  sleep 60
done

# 판정: 6GB가 스왑아웃 같거나 적고 시간이 15% 이내로만 늘면 6GB 유지, 아니면 14GB로 복귀
if (( $SW6 <= $SW14 )) && python3 -c "import sys; sys.exit(0 if $WALL6 <= $WALL14*1.15 else 1)"; then
  KEEP=6; else KEEP=14; restart_workers 14; fi
echo -e "\n## 판정: 워커 예산 ${KEEP}GB 유지 (6GB 조건: 스왑아웃 ≤ 14GB 쪽, 시간 ≤ 1.15배)" >> $OUT
log "판정: ${KEEP}GB 유지. 결과 $OUT"
