#!/bin/bash
set -uo pipefail

ENV_FILE="${ENV_FILE:-${HOME}/server/infra/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

CRITICAL_CONTAINERS=(
  "jenkins"
  "postgres"
  "traefik"
  "landing"
  "autoheal"
)

DISK_THRESHOLD=80
MEM_THRESHOLD=90
LOG_DIR="${HOME}/server/logs"
STATE_DIR="${HOME}/server/logs/state"
mkdir -p "$LOG_DIR" "$STATE_DIR"
LOG_FILE="$LOG_DIR/health-monitor.log"
LAST_STATE_FILE="$STATE_DIR/health-monitor.last"

NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"
nl=$'\n'
issues=()

log() { echo "[$NOW] $*" >> "$LOG_FILE"; }

discord_send_if_changed() {
  local sig="$1" title="$2" desc="$3" color="${4:-15158332}"
  local last_sig=""
  [ -f "$LAST_STATE_FILE" ] && last_sig="$(cat "$LAST_STATE_FILE")"
  [ "$sig" = "$last_sig" ] && return 0
  echo "$sig" > "$LAST_STATE_FILE"
  local webhook="${DISCORD_WEBHOOK_INFRA_ALERTS:-}"
  [ -z "$webhook" ] && return 0
  local payload
  payload=$(jq -nc --arg t "$title" --arg d "$desc" --argjson c "$color" \
    '{embeds: [{title: $t, description: $d, color: $c}]}')
  curl -sS -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null 2>&1 || true
}

for c in "${CRITICAL_CONTAINERS[@]}"; do
  status="$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || echo "missing")"
  health="$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo "")"
  case "$status" in
    "running") [ "$health" = "unhealthy" ] && issues+=("• ${c}: unhealthy") ;;
    "missing") issues+=("• ${c}: 컨테이너 없음") ;;
    *) issues+=("• ${c}: ${status}") ;;
  esac
done

disk_used="$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
[ "$disk_used" -ge "$DISK_THRESHOLD" ] && issues+=("• 디스크: ${disk_used}% 사용 중")

mem_used="$(free | awk '/^Mem:/ {printf "%.0f", ($2-$7)/$2 * 100}')"
[ "$mem_used" -ge "$MEM_THRESHOLD" ] && issues+=("• 메모리: ${mem_used}% 사용 중")

if [ "${#issues[@]}" -eq 0 ]; then
  if [ -f "$LAST_STATE_FILE" ] && [ "$(cat "$LAST_STATE_FILE")" != "OK" ]; then
    discord_send_if_changed "OK" "✅ 인프라 정상 복구" "이전 이슈 해소" 3066993
  fi
  echo "OK" > "$LAST_STATE_FILE"
  log "OK (디스크 ${disk_used}%, 메모리 ${mem_used}%)"
  exit 0
fi

issue_text=$(printf '%s\n' "${issues[@]}")
sig=$(echo "$issue_text" | md5sum | awk '{print $1}')
description="${issue_text}${nl}${nl}디스크 ${disk_used}%, 메모리 ${mem_used}%"

log "이슈 ${#issues[@]}건"
printf '%s\n' "${issues[@]}" >> "$LOG_FILE"
discord_send_if_changed "$sig" "🚨 인프라 이상 (${#issues[@]}건)" "$description" 15158332

exit 1
