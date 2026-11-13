#!/bin/bash
# 4대 스왑아웃 누적 페이지와 스왑 사용량을 한 줄씩 출력 (전후 비교용). 리더(Mac2)에서 실행하며 ssh 별칭 mac1·mac3·mac4 가 있어야 한다.
so='vm_stat | awk "/Swapouts/{gsub(\"\\\\.\",\"\",\$2);print \$2}"; sysctl -n vm.swapusage | awk "{print \$6}"'
echo "mac2 $(bash -c "$so" | tr '\n' ' ')"
echo "mac1 $(ssh -n -o ConnectTimeout=5 mac1 "$so" | tr '\n' ' ')"
echo "mac3 $(ssh -n -o ConnectTimeout=5 mac3 "$so" | tr '\n' ' ')"
echo "mac4 $(ssh -n -o ConnectTimeout=5 mac4 "$so" | tr '\n' ' ')"
