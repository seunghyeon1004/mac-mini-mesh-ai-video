# mac-mini-mesh-ai-video

맥 미니 M4 Pro 24GB 4대를 썬더볼트 5 케이블로 서로 모두 이어 붙여, 한 대로는 버거운 영상 생성 모델 MiniMax H3를 나눠 돌린 기록과 스크립트입니다.
목표는 빠르게 만드는 것이 아니라 **어느 맥도 과부하 없이 30초 영상을 만드는 것**이었습니다.

Four Mac mini M4 Pro (24 GB) machines wired into a full Thunderbolt 5 mesh run the MiniMax H3 video model with [mmh3](https://github.com/niw/mmh3). Scripts, measurements and pitfalls. English summary at the bottom.

- 만든 영상(AI 생성, MiniMax H3): [등대 30초, 카메라 지시 없이](https://youtu.be/QUMDyc7Fv4M) · [새벽 항구 30초, 촬영 지시서로](https://youtu.be/UWLWwA30DeU)
- 과정을 글로 정리한 시리즈: [seunghyeon's lab 블로그](https://blog.naver.com/seunghyeonlab)

## 장비와 소프트웨어

- 맥 미니 M4 Pro 24GB × 4 (Mac1~Mac4), macOS 26.4
- 썬더볼트 5 케이블 6가닥으로 4대 풀메시(모든 쌍 직결)
- [mmh3](https://github.com/niw/mmh3): MiniMax H3 추론 엔진(Rust, 분산 생성 지원), 커밋 `cf3826b6a07c`
- 모델 파일은 한 대당 약 50GB(텍스트 인코더 25 / DiT 20 / VAE 3.2 / FastH3 패치 2.5). 이 저장소에는 들어 있지 않습니다.

## 실측

같은 조건(672×384, 4스텝, FastH3 패치)에서 잰 값입니다.

### 대수별 시간 (3초 영상, MP4까지)

| 구성 | 시간 | 비고 |
|---|---|---|
| 1대 | 338.2초 | 스왑 6.4 → 10.2GB |
| 2대 | 209.0초 | |
| 3대 | 164.8초 | |

### 5초 영상, 4대

| 구성 | 시간 | 스왑아웃 |
|---|---|---|
| 리더는 디코드만, 워커 3대가 DiT + 디코드 | 248.0초 | 워커 1.5~2GB |
| **저부하: 워커 3대는 DiT 스텝만, 리더가 인코딩·디코딩 전담** | 327.6초 | 0 / 0 / 0 / 134MB |

느린 쪽을 골랐습니다. 이 구성으로 5초 클립 6개를 이어 30초 영상을 만드는 동안(클립당 319~339초, 쿨다운 포함 약 40분) 4대 모두 스왑아웃 0MB였습니다.

### 연결별 데이터 교환 (스텝 교환 23.5GB)

| 연결 | 전송 속도 | 걸린 시간 |
|---|---|---|
| 유선 랜 1GbE | 0.09GB/s | 499.57초 |
| 썬더볼트 5 직결 | 4.81~5.70GB/s | 8.13초 (3회 동일) |

여러 대로 나눠 돌릴 때 병목은 칩이 아니라 케이블이었습니다.

## 쓰는 법

1. 각 맥에 번호를 적습니다: `echo 1 > ~/.mesh-node` (Mac1은 1, Mac2는 2 …). 이 구성에서 Mac2가 리더, 1·3·4가 워커입니다.
2. 각 맥에서 `bash scripts/setup.sh`로 mmh3를 고정 커밋으로 받아 빌드합니다. 모델 가중치는 각자 라이선스에 따라 `~/mmh3-dist-bench/models`에 둡니다. 패치와 LoRA는 **모든 맥에 똑같이** 있어야 합니다.
3. `scripts/tb-mesh4.sh`의 `en` 번호를 자기 케이블 배치에 맞게 고친 뒤 각 맥에서 실행합니다. 링크마다 고정 IP를 주고, `/etc/hosts`에 이름을 넣고, 방화벽에 mmh3를 허용합니다. 재부팅 뒤에도 유지하려면 `scripts/install-persistent.sh`를 씁니다.
4. 워커 맥의 **터미널 앱에서** `bash scripts/worker.sh <그 맥의 링크 IP>`를 실행합니다.
5. 리더에서 `bash scripts/check-links.sh <워커 IP…>`로 연결을 확인합니다.
6. 리더에서 `bash scripts/make30.sh scripts/scenes.txt`로 30초 영상을 만듭니다. 장면 파일은 한 줄에 5초짜리 장면 하나입니다.

`make30.sh`는 클립 사이에 쉬고, 스왑이 많으면 기다리고, 로그가 8분 동안 멈추면 리더를 끝내고 그 클립만 다시 시도하며, 중단되면 만든 클립부터 이어서 갑니다. `QUIET=1`을 주면 정한 시간대에만 클립을 시작합니다.

## 겪은 함정

- **썬더볼트 브리지는 끕니다.** 여러 대를 고리 모양으로 이은 상태에서 macOS 기본 Thunderbolt Bridge를 켜면 네트워크가 폭주해 맥이 멈춥니다. 링크마다 고정 IP를 따로 줍니다.
- **방화벽이 말없이 막습니다.** 서명되지 않은 실행 파일이라 연결은 된 것처럼 보이는데 워커가 응답하지 않습니다. 방화벽은 켜 둔 채 mmh3만 허용합니다.
- **2대인데 1대로 돕니다.** 한 맥에 패치 파일이 없으면 워커가 거절하고 리더가 혼자 실행합니다. 에러는 나지 않습니다.
- **이름은 맥마다 다른 주소로 풉니다.** 리더는 워커 주소를 자기가 쓴 문자열 그대로 다른 워커에게 전달합니다. 그래서 IP 대신 이름(`mmh3-n3` 등)을 쓰고, 각 맥의 `/etc/hosts`에서 그 이름을 그 맥 기준 직결 IP로 적습니다.
- **ssh로 띄운 워커는 다른 맥으로 못 나갑니다.** macOS 로컬 네트워크 권한 때문에 "No route to host"가 납니다. 워커는 터미널 앱에서 실행합니다.
- **루프 안의 ssh와 ffmpeg가 입력을 먹습니다.** `while read` 루프가 첫 줄만 처리하고 끝납니다. `ssh -n`, `< /dev/null`, `ffmpeg -nostdin`을 씁니다.
- **`0905` 같은 시각은 8진수로 읽힙니다.** bash 산술에서 오류가 나고 조건이 조용히 실패합니다. `10#`을 붙입니다.
- **리더가 에러 없이 무한 대기할 수 있습니다.** 워커는 계산을 끝냈는데 리더가 결과를 못 받는 경우가 있었습니다. 원인은 아직 확정하지 못했고, 로그가 멈춘 시간을 바깥에서 감시해 재시도하는 것으로 대응했습니다.

## 촬영 지시

5초 클립마다 카메라 움직임을 지시해 본 결과는 [docs/H3-DIRECTING.md](docs/H3-DIRECTING.md)에 있습니다. 요약하면 카메라 움직임(고정, 트래킹, 크레인)은 잘 따르고, 화면에 없던 장소를 새로 보여 주는 컷과 "35mm lens"처럼 물건으로 오해할 수 있는 단어에서 약했습니다. 6컷을 직접 채점한 평균은 약 82%였습니다. 콘티는 `scripts/scenes-harbor.txt`입니다.

## 라이선스와 주의

- 이 저장소의 스크립트와 문서는 MIT 라이선스입니다.
- mmh3는 별도 프로젝트(MIT)이며 이 저장소에 포함하지 않습니다.
- MiniMax H3 가중치는 포함하지 않습니다. MiniMax H3 Community License를 따르며, 한국·미국·EU·영국은 제외 지역이라 별도 승인이 필요합니다. 이 기록은 승인을 받아 진행했습니다.
- 링크한 영상은 AI가 만든 영상입니다(Powered by MiniMax H3).
- 수치는 위 장비에서 잰 값입니다. 다른 구성에서는 달라질 수 있습니다.

## English summary

- **Setup**: 4 × Mac mini M4 Pro 24 GB, six Thunderbolt 5 cables (every pair directly linked), a fixed IP per link, Thunderbolt Bridge off. mmh3 splits the video tokens across machines; every machine still holds the whole DiT.
- **The cable is the bottleneck**: exchanging one step's 23.5 GB took 499.57 s over 1 GbE and 8.13 s over a direct Thunderbolt 5 link.
- **Slower on purpose**: a 5-second clip took 248.0 s with 1.5-2 GB of swap-outs on the workers, or 327.6 s with none when the workers only run DiT steps and the leader does all encoding and decoding. A 30-second video (six chained 5-second clips, each starting from the previous clip's last frame) finished with 0 MB of swap-outs on all four machines.
- **Silent failures** were the hard part: a firewall that drops connections that look established, a missing patch file that makes the leader run alone, loops whose stdin is eaten by ssh and ffmpeg, octal parsing of times like `0905`, and a leader that waits forever. `make30.sh` watches the log from outside and retries a stalled clip.
- Model weights and the mmh3 binary are not included. The linked videos are AI-generated (Powered by MiniMax H3).
