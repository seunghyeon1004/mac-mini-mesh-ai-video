#!/bin/bash
# 30초 영상 = 5초(124프레임) 클립 6개를 이어서 생성. 저부하 구성(Mac1·3·4 DiT만, Mac2 리더+디코드 전담).
# 클립 k(>1)는 앞 클립의 마지막 프레임을 --first-frame으로 받아 장면이 이어지게 한다.
# 각 클립 전에 부하 게이트: 4대 스왑 여유 확인, 조용한 시간대(선택), 클립 사이 쿨다운.
# 사용: bash scripts/make30.sh scripts/scenes.txt   (scenes.txt = 한 줄에 장면 하나, 6줄)
# 한 줄 형식: [CUT ]화면 || 효과음 || 음악   ("CUT "로 시작하면 앞 클립을 이어받지 않고 새로 시작 = 하드컷)
#  "||"가 없으면 화면 설명만 쓴다. H3 공식 형식(integrated_multimodal_description/overall_soundscape/non_diegetic_music)으로 바뀐다.
set -uo pipefail; source "$(dirname "$0")/env.sh"
SCENES=${1:-$BENCH/scripts/scenes.txt}; COOL=${COOL:-60}; MAXSWAP_GB=${MAXSWAP_GB:-12}
RUN=${RUN:-$BENCH/samples/30s-$(date +%Y%m%d-%H%M%S)}; mkdir -p $RUN; LOG=$RUN/run.log   # RUN=기존폴더 주면 있는 클립은 건너뛰고 이어서
WORKERS="--worker mmh3-n1 --worker-units steps --worker mmh3-n3 --worker-units steps --worker mmh3-n4 --worker-units steps"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG; }

gate(){  # 통과할 때까지 기다린다
  while :; do
    hm=$(date +%H%M); busy=""
    # QUIET=1: 다른 작업이 쉬는 시간대에만 클립 시작. 기본 00:30~04:50 (QUIET_FROM/QUIET_TO = HHMM)
    if [ "${QUIET:-0}" = 1 ] && (( 10#$hm < 10#${QUIET_FROM:-0030} || 10#$hm >= 10#${QUIET_TO:-0450} )); then busy="조용한 시간대 아님 $hm"; fi
    if [ -z "$busy" ]; then
      while read -r name so used; do
        u=${used%M}; [ ${u%.*} -gt $((MAXSWAP_GB*1024)) ] && busy="$name 스왑 ${used}"
      done < <(bash $BENCH/scripts/swapmon.sh)
    fi
    [ -z "$busy" ] && return 0
    log "대기: $busy"; sleep 120
  done
}

i=0; PREV=""
while IFS= read -r scene || [ -n "$scene" ]; do
  [ -z "$scene" ] && continue; i=$((i+1))
  [ -s $RUN/clip-$i.mp4 ] && { PREV=$RUN/clip-$i.mp4; log "클립 $i 이미 있음 - 건너뜀"; continue; }
  gate
  P=$RUN/prompt-$i.txt; OUT=$RUN/clip-$i.mp4; FF=""; CUT=0
  case "$scene" in CUT\ *) CUT=1; scene=${scene#CUT };; esac
  if [[ "$scene" == *"||"* ]]; then
    v=${scene%%||*}; rest=${scene#*||}; a=${rest%%||*}; m=""; [[ "$rest" == *"||"* ]] && m=${rest#*||}
    body="integrated_multimodal_description: [Shot 1] $(echo $v)"$'\n'"overall_soundscape: $(echo $a)"
    [ -n "$(echo $m)" ] && body+=$'\n'"non_diegetic_music: $(echo $m)"
  else body=$scene; fi
  if [ -n "$PREV" ] && [ $CUT -eq 0 ]; then
    ffmpeg -nostdin -v error -sseof -0.1 -i "$PREV" -update 1 -frames:v 1 -y $RUN/last-$((i-1)).png
    printf 'For the target video, at 0.00 seconds into the target video, <Picture 1> (from [Shot 1]) is fully referenced.\n\n%s\n' "$body" > $P
    FF="--first-frame $RUN/last-$((i-1)).png"
  else
    printf '%s\n' "$body" > $P
  fi
  log "클립 $i 시작 (cut=$CUT): ${scene:0:90}"; S0=$(bash $BENCH/scripts/swapmon.sh); T0=$(date +%s)
  for TRY in 1 2 3; do   # 멈춤 감시: 로그가 STALL초(기본 480) 동안 안 바뀌면 리더를 죽이고 재시도
    $MMH3 generate --models $MMH3_MODELS --prompt-file $P --seed $((SEED0=${SEED:-1}+i)) \
      --width 672 --height 384 --frames 121 --steps 4 --attention dense --vram-budget 8 \
      --patch minimax_h3_fasth3_vsa_datafree_patch_rank64.safetensors $FF $WORKERS --out $OUT >> $RUN/clip-$i.log 2>&1 < /dev/null &
    PID=$!; STALLED=0
    while kill -0 $PID 2>/dev/null; do
      sleep 20
      if (( $(date +%s) - $(stat -f %m $RUN/clip-$i.log) > ${STALL:-480} )); then
        STALLED=1; log "클립 $i 멈춤 감지(로그 ${STALL:-480}s 정지) - 리더 종료 후 재시도 $TRY/3"; kill $PID; sleep 5; kill -9 $PID 2>/dev/null; break
      fi
    done
    wait $PID; RC=$?
    [ $STALLED -eq 0 ] && break
    echo "=== 재시도 $((TRY+1)) $(date +%T) ===" >> $RUN/clip-$i.log; rm -f $OUT; RC=1; sleep 90
  done
  S1=$(bash $BENCH/scripts/swapmon.sh)
  log "클립 $i 종료 rc=$RC $(( $(date +%s)-T0 ))s | $(paste -d' ' <(echo "$S0") <(echo "$S1") | awk '{printf "%s:+%dMB ",$1,($5-$2)*16/1024}')"
  [ $RC -ne 0 ] && { log "실패 - 중단 (로그 $RUN/clip-$i.log)"; exit 1; }
  [ $CUT -eq 1 ] && touch $RUN/cut-$i
  PREV=$OUT; sleep $COOL
done 3<&- < "$SCENES"

# 이어붙이기: 2번째 클립부터 첫 프레임(앞 클립 마지막과 중복)을 1프레임 잘라낸다
args=(); f=""; n=0
for k in $(seq 1 $i); do args+=(-i $RUN/clip-$k.mp4)
  if [ $k -eq 1 ] || [ -f $RUN/cut-$k ]; then f+="[$((k-1)):v]setpts=PTS-STARTPTS[v$((k-1))];[$((k-1)):a]asetpts=PTS-STARTPTS[a$((k-1))];"
  else f+="[$((k-1)):v]trim=start_frame=1,setpts=PTS-STARTPTS[v$((k-1))];[$((k-1)):a]atrim=start=0.0417,asetpts=PTS-STARTPTS[a$((k-1))];"; fi
  n=$k; done
for k in $(seq 0 $((n-1))); do f+="[v$k][a$k]"; done
ffmpeg -nostdin -v error "${args[@]}" -filter_complex "${f}concat=n=$n:v=1:a=1[v][a]" -map "[v]" -map "[a]" \
  -c:v h264_videotoolbox -b:v 6M -c:a aac -y $RUN/final-30s.mp4
log "완성: $RUN/final-30s.mp4 ($(ffprobe -v error -show_entries format=duration -of csv=p=0 $RUN/final-30s.mp4)s)"
