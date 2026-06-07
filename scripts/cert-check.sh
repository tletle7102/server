#!/bin/bash
set -uo pipefail

ENV_FILE="${ENV_FILE:-${HOME}/server/infra/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

DOMAINS=(
  "${DOMAIN}"
  "traefik.${DOMAIN}"
  "jenkins.${DOMAIN}"
)

WARN_DAYS=30
LOG_DIR="${HOME}/server/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cert-check.log"

NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"
nl=$'\n'
fails=0
warnings=0
alert_summary=""
report_table=""
containers_status=""

log() { echo "[$NOW] $*" | tee -a "$LOG_FILE"; }
alert() {
  if [ -z "$alert_summary" ]; then
    alert_summary="• $*"
  else
    alert_summary="${alert_summary}${nl}• $*"
  fi
}

discord_send() {
  local webhook="$1"
  local title="$2"
  local desc="$3"
  local color="${4:-3447003}"
  [ -z "$webhook" ] && return 0
  local payload
  payload=$(jq -nc --arg t "$title" --arg d "$desc" --argjson c "$color" \
    '{embeds: [{title: $t, description: $d, color: $c}]}')
  curl -sS -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null 2>&1 || true
}

log "===== 헬스체크 시작 ====="

for domain in "${DOMAINS[@]}"; do
  cert="$(echo | timeout 10 openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null \
          | openssl x509 -noout -dates 2>/dev/null)"
  if [ -z "$cert" ]; then
    report_table="${report_table}• ${domain}: ❌ 응답 없음${nl}"
    alert "$domain: SSL/443 응답 없음"
    fails=$((fails + 1))
    continue
  fi
  not_after="$(echo "$cert" | grep notAfter | cut -d= -f2)"
  not_after_epoch="$(date -d "$not_after" +%s)"
  now_epoch="$(date +%s)"
  days_left=$(( (not_after_epoch - now_epoch) / 86400 ))
  http_code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "https://$domain" 2>/dev/null || echo "000")"
  emoji="✅"
  if [ "$days_left" -lt "$WARN_DAYS" ]; then
    emoji="⚠️"
    warnings=$((warnings + 1))
    alert "$domain: 인증서 ${days_left}일 남음"
  fi
  if [ "$http_code" != "200" ] && [ "$http_code" != "401" ] && [ "$http_code" != "403" ]; then
    emoji="❌"
    fails=$((fails + 1))
    alert "$domain: HTTPS 비정상 ($http_code)"
  fi
  log "$domain | 만료까지 ${days_left}일 | HTTP $http_code | $emoji"
  report_table="${report_table}• ${domain}: ${days_left}일 남음 (HTTP ${http_code}) ${emoji}${nl}"
done

while IFS= read -r line; do
  containers_status="${containers_status}• ${line}${nl}"
done < <(docker ps --format "{{.Names}}: {{.Status}}")
unhealthy="$(docker ps --filter health=unhealthy --format '{{.Names}}' || true)"
if [ -n "$unhealthy" ]; then
  for c in $unhealthy; do alert "$c: unhealthy"; done
  fails=$((fails + 1))
fi

overall="✅"
overall_color=3066993
if [ "$fails" -gt 0 ]; then overall="❌"; overall_color=15158332; \
elif [ "$warnings" -gt 0 ]; then overall="⚠️"; overall_color=15844367; fi

daily_desc="**SSL 인증서**${nl}${report_table}${nl}**컨테이너**${nl}${containers_status}${nl}**결과**: FAIL=${fails}, WARN=${warnings}"
discord_send "${DISCORD_WEBHOOK_DAILY_REPORTS:-}" "${overall} 헬스체크 (${NOW})" "$daily_desc" "$overall_color"

if [ $((fails + warnings)) -gt 0 ]; then
  alert_desc="**FAIL=${fails} WARN=${warnings}**${nl}${nl}${alert_summary}"
  discord_send "${DISCORD_WEBHOOK_INFRA_ALERTS:-}" "🚨 인프라 이상" "$alert_desc" 15158332
fi

log "===== 결과: FAIL=$fails WARN=$warnings ====="
exit $(( (fails + warnings) > 0 ? 1 : 0 ))
