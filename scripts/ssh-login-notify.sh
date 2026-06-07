#!/bin/bash
set -uo pipefail

ENV_FILE="${ENV_FILE:-${HOME}/server/infra/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

WEBHOOK="${DISCORD_WEBHOOK_SECURITY:-}"
[ -z "$WEBHOOK" ] && exit 0

WHO="$(whoami)"
HOSTNAME="$(hostname)"
SOURCE_IP="${SSH_CONNECTION%% *}"
[ -z "$SOURCE_IP" ] && SOURCE_IP="unknown"
WHEN="$(date '+%Y-%m-%d %H:%M:%S %Z')"

{
  payload=$(jq -nc \
    --arg t "🔐 SSH 로그인" \
    --arg d "**사용자**: ${WHO}\n**서버**: ${HOSTNAME}\n**원격 IP**: ${SOURCE_IP}\n**시각**: ${WHEN}" \
    --argjson c 16753920 \
    '{embeds: [{title: $t, description: $d, color: $c}]}')
  curl -sS -H "Content-Type: application/json" -d "$payload" "$WEBHOOK" >/dev/null 2>&1 || true
} &
disown
exit 0
