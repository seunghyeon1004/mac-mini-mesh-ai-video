#!/bin/bash
# mmh3 4대 구성 영구화 (각 맥에서 1회, 관리자 비밀번호 1번)
#  1) 재부팅·케이블 재연결 때 TB 링크 고정 IP 자동 복구 (root LaunchDaemon com.mmh3.tbmesh)
#  2) /etc/hosts 이름 + 방화벽 mmh3 허용 (기존 tb-mesh4.sh와 동일, 다시 해도 안전)
#  3) 워커 맥(1·3·4): 로그인하면 터미널에서 워커 자동 시작, 죽으면 5초 뒤 재시작 (LaunchAgent com.mmh3.worker)
# 되돌리기: bash install-persistent.sh --uninstall
set -euo pipefail
BENCH=$HOME/mmh3-dist-bench
case $(cat ~/.mesh-node 2>/dev/null) in
  1) A="en4 10.77.12.1|en2 10.77.13.1|en3 10.77.14.1"; H="10.77.12.1 mmh3-n1|10.77.13.3 mmh3-n3|10.77.14.4 mmh3-n4"; WIP=10.77.12.1 ;;
  2) A="en4 10.77.12.2|en3 10.77.23.2|en2 10.77.24.2"; H="10.77.12.1 mmh3-n1|10.77.23.3 mmh3-n3|10.77.24.4 mmh3-n4"; WIP="" ;;
  3) A="en3 10.77.13.3|en4 10.77.23.3|en2 10.77.34.3"; H="10.77.13.1 mmh3-n1|10.77.23.3 mmh3-n3|10.77.34.4 mmh3-n4"; WIP=10.77.23.3 ;;
  4) A="en4 10.77.14.4|en3 10.77.24.4|en2 10.77.34.4"; H="10.77.14.1 mmh3-n1|10.77.34.3 mmh3-n3|10.77.24.4 mmh3-n4"; WIP=10.77.24.4 ;;
  *) echo "~/.mesh-node 에 이 맥의 번호(1~4)를 적어 주세요"; exit 1 ;;
esac
DAEMON=/Library/LaunchDaemons/com.mmh3.tbmesh.plist; HELPER=/usr/local/libexec/mmh3-tbmesh.sh
AGENT=$HOME/Library/LaunchAgents/com.mmh3.worker.plist

if [ "${1:-}" = --uninstall ]; then
  sudo launchctl bootout system/com.mmh3.tbmesh 2>/dev/null || true; sudo rm -f $DAEMON $HELPER
  launchctl bootout gui/$(id -u)/com.mmh3.worker 2>/dev/null || true; rm -f $AGENT
  echo "제거 완료 (IP·hosts·방화벽 규칙은 그대로)"; exit 0
fi

# 1) TB IP 복구 도우미: root 소유 위치에 복사 (사용자 폴더 스크립트를 root로 돌리지 않기 위해)
TMP=$(mktemp)
cat > $TMP <<EOF
#!/bin/bash
# 없는 링크 IP만 붙인다. 케이블이 빠진 포트는 건너뛴다.
for a in $(echo "$A" | tr '|' ' ' | sed 's/ 10/:10/g'); do
  i=\${a%%:*}; ip=\${a#*:}
  ifconfig \$i >/dev/null 2>&1 || continue
  ifconfig \$i | grep -q "inet \$ip " || ifconfig \$i alias \$ip/24
done
EOF
sudo mkdir -p /usr/local/libexec; sudo install -o root -g wheel -m 755 $TMP $HELPER; rm -f $TMP
sudo tee $DAEMON >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.mmh3.tbmesh</string>
  <key>ProgramArguments</key><array><string>$HELPER</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
  <key>WatchPaths</key><array><string>/Library/Preferences/SystemConfiguration</string></array>
</dict></plist>
EOF
sudo chown root:wheel $DAEMON; sudo chmod 644 $DAEMON
sudo launchctl bootout system/com.mmh3.tbmesh 2>/dev/null || true
sudo launchctl bootstrap system $DAEMON

# 2) hosts + 방화벽
sudo sed -i '' '/# mmh3-tb$/d' /etc/hosts
echo "$H" | tr '|' '\n' | sed 's/$/ # mmh3-tb/' | sudo tee -a /etc/hosts >/dev/null
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $BENCH/src/target/release/mmh3 >/dev/null
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp $BENCH/src/target/release/mmh3 >/dev/null
sudo dscacheutil -flushcache

# 3) 워커 자동 시작 (Mac2는 리더라 없음). 터미널 경유 = 로컬 네트워크 권한 문제 회피
if [ -n "$WIP" ]; then
  [ -f $BENCH/worker.conf ] || echo "VRAM_BUDGET=14" > $BENCH/worker.conf
  cat > $AGENT <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.mmh3.worker</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>Terminal</string><string>$BENCH/scripts/worker-start.command</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
  launchctl bootout gui/$(id -u)/com.mmh3.worker 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) $AGENT
fi
sleep 3
echo; ifconfig | grep "inet 10.77"; grep mmh3-tb /etc/hosts
sudo launchctl print system/com.mmh3.tbmesh | grep -E "state|runs" | head -2
[ -n "$WIP" ] && pgrep -fl "worker-start|mmh3 worker"
echo "완료 - 이 창은 닫아도 됩니다"
