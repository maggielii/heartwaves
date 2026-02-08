#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT_DIR/tmp/server.pid"
LOG_FILE="$ROOT_DIR/tmp/server.log"
PORT="4567"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

mkdir -p "$ROOT_DIR/tmp"

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  kill -0 "$pid" 2>/dev/null
}

port_pid() {
  lsof -nP -iTCP:${PORT} -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

start_server() {
  local listening_pid
  listening_pid="$(port_pid)"
  if [[ -n "$listening_pid" ]]; then
    echo "Port ${PORT} already in use by pid=${listening_pid}. Reusing existing server."
    return 0
  fi

  if is_running; then
    echo "HeartWaves server already running (pid=$(cat "$PID_FILE"))."
    return 0
  fi

  echo "Starting HeartWaves server on http://127.0.0.1:${PORT} ..."
  (
    cd "$ROOT_DIR"
    nohup ruby server.rb >>"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
  )

  local ok="0"
  for _ in {1..20}; do
    if curl -sS "$HEALTH_URL" >/dev/null 2>&1; then
      ok="1"
      break
    fi
    sleep 0.4
  done

  if [[ "$ok" == "1" ]]; then
    echo "Server started (pid=$(cat "$PID_FILE"))."
    echo "Log: $LOG_FILE"
  else
    echo "Server did not become healthy. See logs:"
    tail -n 60 "$LOG_FILE" || true
    return 1
  fi
}

stop_server() {
  if ! is_running; then
    local listening_pid
    listening_pid="$(port_pid)"
    if [[ -n "$listening_pid" ]]; then
      echo "Stopping server on port ${PORT} (pid=${listening_pid}) ..."
      kill "$listening_pid" 2>/dev/null || true
      sleep 0.4
      if kill -0 "$listening_pid" 2>/dev/null; then
        kill -9 "$listening_pid" 2>/dev/null || true
      fi
      rm -f "$PID_FILE"
      echo "Server stopped."
      return 0
    fi

    echo "HeartWaves server is not running."
    rm -f "$PID_FILE"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  echo "Stopping server pid=$pid ..."
  kill "$pid" 2>/dev/null || true
  sleep 0.4
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "Server stopped."
}

status_server() {
  local listening_pid
  listening_pid="$(port_pid)"

  if is_running; then
    echo "RUNNING pid=$(cat "$PID_FILE")"
  elif [[ -n "$listening_pid" ]]; then
    echo "RUNNING pid=${listening_pid} (external)"
  else
    echo "STOPPED"
  fi
  if curl -sS "$HEALTH_URL" >/dev/null 2>&1; then
    echo "HEALTH OK $HEALTH_URL"
  else
    echo "HEALTH DOWN $HEALTH_URL"
  fi
}

logs_server() {
  touch "$LOG_FILE"
  tail -n 80 "$LOG_FILE"
}

open_ui() {
  open -a Safari "http://127.0.0.1:${PORT}/react/"
}

cmd="${1:-}"
case "$cmd" in
  start) start_server ;;
  stop) stop_server ;;
  restart) stop_server; start_server ;;
  status) status_server ;;
  logs) logs_server ;;
  open) open_ui ;;
  *)
    cat <<EOF
Usage: scripts/mvp_server.sh <start|stop|restart|status|logs|open>
EOF
    exit 1
    ;;
esac
