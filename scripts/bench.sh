#!/bin/bash
# 같은 컷을 고정 조건으로 생성하고 전체 시간·DiT 시간을 기록한다.
# 사용: bash scripts/bench.sh <라벨> [mmh3 generate 추가 인자...]
#  1대: bash scripts/bench.sh n1
#  2대: bash scripts/bench.sh n2 --local-worker --worker 10.23.0.3
#  4대: bash scripts/bench.sh n4 --local-worker --worker A --worker B --worker C
# 주의: 모델 가중치는 각자 MiniMax H3 라이선스에 따라 받는다(한국·미국·EU·영국은 제외 지역이라 별도 승인이 필요).
set -uo pipefail; source "$(dirname "$0")/env.sh"
LABEL=$1; shift
PROMPT_FILE=$BENCH/scripts/prompt.txt
SEED=${SEED:-42}; W=${W:-640}; H=${H:-384}; FRAMES=${FRAMES:-121}; STEPS=${STEPS:-8}; ATTN=${ATTN:-dense}
TS=$(date +%Y%m%d-%H%M%S); LOG=$BENCH/logs/bench-$LABEL-$TS.log; MP4=$BENCH/samples/$LABEL-$TS.mp4
{ echo "# label=$LABEL seed=$SEED ${W}x${H} frames=$FRAMES steps=$STEPS attention=$ATTN commit=$MMH3_COMMIT"
  echo "# args: $*"; sysctl vm.swapusage; } > $LOG
T0=$(python3 -c 'import time;print(time.time())')
$MMH3 generate --models $MMH3_MODELS --prompt-file $PROMPT_FILE --seed $SEED \
  --width $W --height $H --frames $FRAMES --steps $STEPS --attention $ATTN \
  --vram-budget ${VRAM_BUDGET:-14} --out $MP4 "$@" 2>&1 | tee -a $LOG
RC=${PIPESTATUS[0]}
T1=$(python3 -c 'import time;print(time.time())')
{ echo "# exit=$RC wall_to_mp4=$(python3 -c "print(round($T1-$T0,1))")s"; sysctl vm.swapusage
  ffprobe -v error -show_entries stream=codec_type,codec_name,duration -of csv=p=0 $MP4 2>&1; } | tee -a $LOG
