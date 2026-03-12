#!/bin/sh
# run_and_record.sh
# roslaunch 실행 + 터미널 로그 저장 + rosbag 녹화 통합 스크립트
# POSIX sh 호환 (i.MX8 등 임베디드 환경 지원)

# ── 설정 ──
LAUNCH_PKG="epic_planner"
LAUNCH_FILE="avia.launch"
LOG_DIR="$HOME/epic_logs"
BAG_DIR="$HOME/epic_bags"
TOPICS=""  # 녹화할 토픽 (빈 값이면 rosbag 녹화 안 함, -a 넣으면 전체 녹화)
           # 예: TOPICS="/odom /scan /tf"

# ── 타임스탬프 ──
STAMP=$(date +%Y%m%d_%H%M%S)

# ── 디렉토리 생성 ──
mkdir -p "$LOG_DIR" "$BAG_DIR"

LOG_FILE="$LOG_DIR/epic_${STAMP}.log"
BAG_PREFIX="$BAG_DIR/epic_${STAMP}"

# ── 정리 함수 ──
cleanup() {
    echo ""
    echo "[run_and_record] Shutting down..."

    if [ -n "$BAG_PID" ] && kill -0 "$BAG_PID" 2>/dev/null; then
        kill -INT "$BAG_PID" 2>/dev/null
        wait "$BAG_PID" 2>/dev/null
        echo "[run_and_record] rosbag stopped"
    fi

    if [ -n "$LAUNCH_PID" ] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
        kill -INT "$LAUNCH_PID" 2>/dev/null
        wait "$LAUNCH_PID" 2>/dev/null
        echo "[run_and_record] roslaunch stopped"
    fi

    echo "[run_and_record] Log  : $LOG_FILE"
    [ -n "$TOPICS" ] && echo "[run_and_record] Bag  : ${BAG_PREFIX}*.bag"
    echo "[run_and_record] Done."
    exit 0
}

trap cleanup INT TERM

# ── roslaunch 실행 + 로그 저장 ──
echo "[run_and_record] Starting roslaunch ${LAUNCH_PKG} ${LAUNCH_FILE}"
echo "[run_and_record] Log file: ${LOG_FILE}"

roslaunch "$LAUNCH_PKG" "$LAUNCH_FILE" 2>&1 | tee "$LOG_FILE" &
LAUNCH_PID=$!

# launch 노드가 뜰 시간 확보
sleep 3

# ── rosbag 녹화 ──
BAG_PID=""
if [ -n "$TOPICS" ]; then
    if [ "$TOPICS" = "-a" ]; then
        echo "[run_and_record] Recording ALL topics"
        rosbag record -a -o "$BAG_PREFIX" &
        BAG_PID=$!
    else
        echo "[run_and_record] Recording topics: ${TOPICS}"
        # shellcheck disable=SC2086
        rosbag record -o "$BAG_PREFIX" $TOPICS &
        BAG_PID=$!
    fi
else
    echo "[run_and_record] TOPICS is empty, skipping rosbag record"
fi

# ── roslaunch 종료 대기 ──
wait "$LAUNCH_PID" 2>/dev/null
cleanup
