#!/bin/bash
# 4대 TB 풀메시: 링크별 고정 IP + 맥별 /etc/hosts 이름(mmh3-n1/n3/n4) + mmh3 방화벽 허용. 재부팅 시 IP 사라짐.
# 링크(서브넷 10.77.AB.0/24, 호스트 끝자리=맥번호):
#  1-2 Mac1 en4↔Mac2 en4 | 1-3 Mac1 en2↔Mac3 en3 | 1-4 Mac1 en3↔Mac4 en4
#  2-3 Mac2 en3↔Mac3 en4 | 2-4 Mac2 en2↔Mac4 en3 | 3-4 Mac3 en2↔Mac4 en2
# 되돌리기: sudo sed -i '' '/# mmh3-tb$/d' /etc/hosts  (+재부팅 또는 ifconfig enX -alias IP)
# 먼저 각 맥에서: echo 1 > ~/.mesh-node  (그 맥의 번호 1~4). en 번호는 케이블을 꽂은 포트에 따라 다르니 ifconfig로 확인해 고친다.
set -e
MMH3=$HOME/mmh3-dist-bench/src/target/release/mmh3
case $(cat ~/.mesh-node 2>/dev/null) in
  1) A="en4 10.77.12.1|en2 10.77.13.1|en3 10.77.14.1"; H="10.77.12.1 mmh3-n1|10.77.13.3 mmh3-n3|10.77.14.4 mmh3-n4" ;;
  2) A="en4 10.77.12.2|en3 10.77.23.2|en2 10.77.24.2"; H="10.77.12.1 mmh3-n1|10.77.23.3 mmh3-n3|10.77.24.4 mmh3-n4" ;;
  3) A="en3 10.77.13.3|en4 10.77.23.3|en2 10.77.34.3"; H="10.77.13.1 mmh3-n1|10.77.23.3 mmh3-n3|10.77.34.4 mmh3-n4" ;;
  4) A="en4 10.77.14.4|en3 10.77.24.4|en2 10.77.34.4"; H="10.77.14.1 mmh3-n1|10.77.34.3 mmh3-n3|10.77.24.4 mmh3-n4" ;;
esac
IFS='|'; for a in $A; do set -- ${a% *} ${a#* }; sudo ifconfig $1 alias $2/24; done
sudo sed -i '' '/# mmh3-tb$/d' /etc/hosts
for h in $H; do echo "$h # mmh3-tb" | sudo tee -a /etc/hosts >/dev/null; done; unset IFS
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $MMH3 >/dev/null
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp $MMH3 >/dev/null
sudo dscacheutil -flushcache
ifconfig | grep "inet 10.77"; grep mmh3-tb /etc/hosts; echo "완료 - 이 창은 닫아도 됩니다"
