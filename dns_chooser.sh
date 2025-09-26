#!/usr/bin/env bash
# dns-test — тестирует список DNS серверов и выводит топ лучших (только тест, ничего не применяет)
# Usage:
#   dns-test              # тестирует встроенный список и выводит топ 5
#   dns-test --top 10     # вывести топ 10
#   dns-test --file path  # читать сервера из файла (one server per line)
#   dns-test --count 3    # сколько запросов на сервер (по умолчанию 3)
#   dns-test --help

set -euo pipefail
IFS=$'\n\t'

TOP_N=5
REQ_COUNT=3
SERVERS_FILE=""
TIMEOUT=2

print_help() {
  cat <<EOF
dns-test — тестирует DNS серверы и показывает лучшие.

Options:
  --top N        Показать топ N серверов (по умолчанию 5)
  --file PATH    Список серверов (по одному на строку). Комментарии # игнорируются.
  --count N      Сколько запросов на сервер (dig или ping). По умолчанию 3.
  --timeout N    Таймаут в секундах для запросов (dig/ping). По умолчанию 2.
  --help
EOF
}

# Default list (~20 популярных)
DEFAULT_SERVERS=(
  1.1.1.1
  1.0.0.1
  8.8.8.8
  8.8.4.4
  9.9.9.9
  149.112.112.112
  94.140.14.14
  94.140.15.15
  45.11.45.11
  76.76.19.19
  76.223.122.150
  64.6.64.6
  64.6.65.6
  84.200.69.80
  84.200.70.40
  23.253.163.53
  45.90.28.0
  77.88.8.8
  77.88.8.1
  208.67.222.222
)

while [[ "${#}" -gt 0 ]]; do
  case "$1" in
    --top) TOP_N="$2"; shift 2 ;;
    --file) SERVERS_FILE="$2"; shift 2 ;;
    --count) REQ_COUNT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown arg: $1"; print_help; exit 1 ;;
  esac
done

# read server list
read_servers() {
  if [[ -n "$SERVERS_FILE" ]]; then
    if [[ ! -f "$SERVERS_FILE" ]]; then
      echo "File not found: $SERVERS_FILE" >&2
      exit 2
    fi
    mapfile -t servers < <(grep -E -v '^\s*(#|$)' "$SERVERS_FILE" | awk '{print $1}')
  else
    servers=("${DEFAULT_SERVERS[@]}")
  fi
}

# try dig, fallback to ping
# returns: "server|avg_ms|loss_percent|method"
measure_with_dig() {
  local srv="$1"
  local count="$2"
  local t="$3"
  # use 'dig +stats +time=<t>' and measure query time lines
  local times=()
  for i in $(seq 1 "$count"); do
    # query a common domain; use short form and silent errors
    if out=$(dig +noall +stats +time="$t" @"$srv" google.com A 2>/dev/null); then
      # parse "Query time: 24 msec"
      qt=$(printf '%s\n' "$out" | awk -F': ' '/Query time:/ {gsub(" msec","",$2); print $2; exit}')
      if [[ -n "$qt" ]]; then
        times+=("$qt")
      else
        times+=("9999")
      fi
    else
      times+=("9999")
    fi
  done

  # compute average
  local sum=0
  local n=0
  for v in "${times[@]}"; do
    sum=$((sum + v))
    n=$((n + 1))
  done
  local avg=$((sum / n))
  # loss: count how many are 9999
  local lost=0
  for v in "${times[@]}"; do
    [[ "$v" -ge 9999 ]] && lost=$((lost+1))
  done
  local loss_percent=$(( (lost * 100) / count ))
  printf '%s|%s|%s|dig' "$srv" "$avg" "$loss_percent"
}

measure_with_ping() {
  local srv="$1"
  local count="$2"
  local t="$3"
  # use ping summary
  if out=$(ping -c "$count" -W "$t" -q "$srv" 2>/dev/null); then
    loss=$(printf '%s\n' "$out" | awk -F', ' '/packet loss/ {gsub("%","",$3); print $3}' | tr -d '[:space:]' )
    rtt=$(printf '%s\n' "$out" | awk -F'= ' '/rtt/ {print $2}' | awk -F'/' '{print $2}')
    if [[ -z "$rtt" ]]; then rtt=9999; fi
    rtt_int=$(printf '%.0f' "$rtt" 2>/dev/null || echo 9999)
    printf '%s|%s|%s|ping' "$srv" "$rtt_int" "$loss"
  else
    # failed ping
    printf '%s|%s|%s|ping' "$srv" "9999" "100"
  fi
}

measure_server() {
  local srv="$1"
  # prefer dig if available
  if command -v dig >/dev/null 2>&1; then
    measure_with_dig "$srv" "$REQ_COUNT" "$TIMEOUT"
  else
    measure_with_ping "$srv" "$REQ_COUNT" "$TIMEOUT"
  fi
}

# score: lower avg is better; heavy penalty for loss
# We'll compute score = avg_ms * (1 + loss_percent/100 * 5)
# i.e. 100% loss -> score *= 6 (very bad)
score_line() {
  local srv="$1"; local avg="$2"; local loss="$3"; local method="$4"
  # ensure integers
  avg=${avg:-9999}
  loss=${loss:-100}
  # compute score with bc
  score=$(awk -v a="$avg" -v l="$loss" 'BEGIN { printf "%.2f", a * (1 + (l/100)*5) }')
  printf '%s|%s|%s|%s|%s' "$srv" "$avg" "$loss" "$method" "$score"
}

main() {
  read_servers
  echo "Тестируем ${#servers[@]} серверов (по $REQ_COUNT запросов). Это только замер — изменений в системе не будет."
  results=()
  for s in "${servers[@]}"; do
    printf 'Тест %s ... ' "$s"
    line=$(measure_server "$s")
    # line: server|avg|loss|method
    IFS='|' read -r srv avg loss method <<<"$line"
    scored=$(score_line "$srv" "$avg" "$loss" "$method")
    results+=("$scored")
    printf 'avg=%sms loss=%s%% method=%s score=%s\n' "$avg" "$loss" "$method" "$(echo "$scored" | awk -F'|' '{print $5}')"
  done

  # sort by score numeric asc
  IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t'|' -k5n))
  echo
  echo "Топ ${TOP_N} DNS по результатам (лучшие сверху):"
  printf '%-3s %-16s %-8s %-8s %-8s\n' "#" "SERVER" "AVG(ms)" "LOSS(%)" "SCORE"
  i=0
  for r in "${sorted[@]}"; do
    i=$((i+1))
    srv=$(echo "$r" | awk -F'|' '{print $1}')
    avg=$(echo "$r" | awk -F'|' '{print $2}')
    loss=$(echo "$r" | awk -F'|' '{print $3}')
    method=$(echo "$r" | awk -F'|' '{print $4}')
    score=$(echo "$r" | awk -F'|' '{print $5}')
    printf '%-3d %-16s %-8s %-8s %-8s\n' "$i" "$srv" "$avg" "$loss" "$score"
    if [[ $i -ge $TOP_N ]]; then break; fi
  done
}

main "$@"
