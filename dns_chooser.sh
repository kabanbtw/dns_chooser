#!/usr/bin/env bash
# dns-test — Tests a list of DNS servers and displays the top performers (testing only, no system changes).
# Usage:
#   dns-test              # Tests default list and shows top 5
#   dns-test --top 10     # Show top 10 servers
#   dns-test --file path  # Read servers from file (one server per line)
#   dns-test --count 3    # Number of requests per server (dig or ping). Default: 3
#   dns-test --timeout 2  # Timeout in seconds for requests (dig/ping). Default: 2
#   dns-test --lang en    # Set language (en or ru, default: based on $LANG)
#   dns-test --version    # Show version
#   dns-test --help

set -euo pipefail
IFS=$'\n\t'

VERSION="2.0.0"
TOP_N=5
REQ_COUNT=3
TIMEOUT=2
SERVERS_FILE=""
LOG_FILE="$HOME/.dns-test.log"

# Определяем язык (по умолчанию русский)
LANGUAGE=${LANG:-ru_RU}
LANGUAGE=${LANGUAGE:0:2}

# Словари с переводами
declare -A MESSAGES_ru
declare -A MESSAGES_en

MESSAGES_ru=(
    ["help"]="dns-test — тестирует DNS серверы и показывает лучшие.\n\nОпции:\n  --top N        Показать топ N серверов (по умолчанию 5)\n  --file PATH    Список серверов (по одному на строку). Комментарии # игнорируются.\n  --count N      Сколько запросов на сервер (dig или ping). По умолчанию 3.\n  --timeout N    Таймаут в секундах для запросов (dig/ping). По умолчанию 2.\n  --lang ru|en   Установить язык (по умолчанию: ru)\n  --version      Показать версию\n  --help\n"
    ["unknown_arg"]="Неизвестный аргумент: "
    ["file_not_found"]="Файл не найден: "
    ["invalid_number"]="Ошибка: %s должен быть положительным целым числом"
    ["invalid_ip"]="Некорректный IP-адрес: %s"
    ["testing"]="Тестируем %s серверов (по %s запросов). Это только замер — изменений в системе не будет."
    ["top_results"]="Топ %s DNS по результатам (лучшие сверху):"
    ["no_internet"]="❌ Нет подключения к интернету. Проверьте соединение."
    ["check_internet_tip"]="Попробуйте проверить соединение командой 'dig @1.1.1.1 google.com' или откройте сайт в браузере."
    ["test"]="Тест %s ... "
    ["method_note"]="Метод: %s (dig предпочтительнее, ping — запасной)"
    ["total_time"]="Общее время тестирования: %s секунд"
)

MESSAGES_en=(
    ["help"]="dns-test — Tests DNS servers and displays the best performers.\n\nOptions:\n  --top N        Show top N servers (default: 5)\n  --file PATH    List of servers (one per line). Comments with # are ignored.\n  --count N      Number of requests per server (dig or ping). Default: 3.\n  --timeout N    Timeout in seconds for requests (dig/ping). Default: 2.\n  --lang ru|en   Set language (default: based on \$LANG)\n  --version      Show version\n  --help\n"
    ["unknown_arg"]="Unknown argument: "
    ["file_not_found"]="File not found: "
    ["invalid_number"]="Error: %s must be a positive integer"
    ["invalid_ip"]="Invalid IP address: %s"
    ["testing"]="Testing %s servers (%s requests each). This is a test only — no system changes."
    ["top_results"]="Top %s DNS servers by performance (best first):"
    ["no_internet"]="❌ No internet connection. Please check your connection."
    ["check_internet_tip"]="Try checking your connection with 'dig @1.1.1.1 google.com' or open a website in your browser."
    ["test"]="Testing %s ... "
    ["method_note"]="Method: %s (dig preferred, ping as fallback)"
    ["total_time"]="Total testing time: %s seconds"
)

# Функция для получения переведенной строки
get_message() {
    local key=$1
    shift
    case $LANGUAGE in
        en) printf "${MESSAGES_en[$key]}" "$@" ;;
        *) printf "${MESSAGES_ru[$key]}" "$@" ;; # По умолчанию русский
    esac
}

print_help() {
    echo -e "$(get_message 'help')"
}

print_version() {
    echo "dns-test v$VERSION"
}

# Проверка положительного целого числа
validate_number() {
    local name=$1 value=$2
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo "$(get_message 'invalid_number' "$name")" >&2
        exit 1
    fi
}

# Проверка корректности IP-адреса
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$(get_message 'invalid_ip' "$ip")" >&2
        return 1
    fi
    # Проверка, что каждый октет в диапазоне 0-255
    IFS='.' read -r a b c d <<<"$ip"
    if [[ $a -gt 255 || $b -gt 255 || $c -gt 255 || $d -gt 255 ]]; then
        echo "$(get_message 'invalid_ip' "$ip")" >&2
        return 1
    fi
}

# Проверка сетевого соединения
check_internet() {
    if ! dig +noall +stats +time=3 @1.1.1.1 google.com A >/dev/null 2>&1; then
        echo "$(get_message 'no_internet')" >&2
        echo "$(get_message 'check_internet_tip')" >&2
        exit 1
    fi
}

# Default list (обновленный список с комментариями)
DEFAULT_SERVERS=(
    1.1.1.1           # Cloudflare: высокая скорость, DoH/DoT, приватность
    1.0.0.1           # Cloudflare: альтернативный
    8.8.8.8           # Google Public DNS: высокая доступность
    9.9.9.9           # Quad9: безопасность, блокировка вредоносных доменов, DoH/DoT
    94.140.14.14      # AdGuard: блокировка рекламы и трекеров, DoH/DoT
    208.67.222.222    # OpenDNS by Cisco: надежность, фильтрация
    77.88.8.8         # Yandex DNS: оптимизирован для России
    149.112.112.112   # Quad9: альтернативный, безопасный
    185.228.168.168   # CleanBrowsing: семейный фильтр, DoH/DoT
    76.76.2.2         # Control D: высокая скорость, кастомизация, DoH/DoT
    45.90.28.0        # NextDNS: кастомная фильтрация, DoH/DoT
    84.200.69.80      # DNS.Watch: без логов, высокая приватность
    5.2.75.75         # Mullvad DNS: приватность, DoH, без логов
    194.187.251.67    # Comodo Secure DNS: безопасность, фильтрация
    80.80.80.80       # Freenom World: простота, высокая доступность
)

# Чтение списка серверов
read_servers() {
    if [[ -n "$SERVERS_FILE" ]]; then
        if [[ ! -f "$SERVERS_FILE" ]]; then
            echo "$(get_message 'file_not_found' "$SERVERS_FILE")" >&2
            exit 2
        fi
        mapfile -t servers < <(grep -E -v '^\s*(#|$)' "$SERVERS_FILE" | awk '{print $1}')
    else
        servers=("${DEFAULT_SERVERS[@]}")
    fi
    # Проверка валидности IP-адресов
    for s in "${servers[@]}"; do
        validate_ip "$s" || exit 1
    done
}

# Тестирование с dig
measure_with_dig() {
    local srv="$1" count="$2" t="$3"
    local times=()
    for i in $(seq 1 "$count"); do
        if out=$(dig +noall +stats +time="$t" @"$srv" google.com A 2>/dev/null); then
            qt=$(printf '%s\n' "$out" | awk -F': ' '/Query time:/ {gsub(" msec","",$2); print $2; exit}')
            times+=("${qt:-9999}")
        else
            times+=("9999")
        fi
    done
    local sum=0 n=0
    for v in "${times[@]}"; do
        sum=$((sum + v))
        n=$((n + 1))
    done
    local avg=$((sum / n))
    local lost=0
    for v in "${times[@]}"; do
        [[ "$v" -ge 9999 ]] && lost=$((lost + 1))
    done
    local loss_percent=$(( (lost * 100) / count ))
    printf '%s|%s|%s|dig' "$srv" "$avg" "$loss_percent"
}

# Тестирование с ping
measure_with_ping() {
    local srv="$1" count="$2" t="$3"
    if out=$(ping -c "$count" -W "$t" -q "$srv" 2>/dev/null); then
        loss=$(printf '%s\n' "$out" | awk -F', ' '/packet loss/ {gsub("%","",$3); print $3}' | tr -d '[:space:]')
        rtt=$(printf '%s\n' "$out" | awk -F'= ' '/rtt/ {print $2}' | awk -F'/' '{print $2}')
        rtt_int=$(printf '%.0f' "${rtt:-9999}" 2>/dev/null || echo 9999)
        printf '%s|%s|%s|ping' "$srv" "$rtt_int" "${loss:-100}"
    else
        printf '%s|%s|%s|ping' "$srv" "9999" "100"
    fi
}

# Выбор метода тестирования
measure_server() {
    local srv="$1"
    if command -v dig >/dev/null 2>&1; then
        measure_with_dig "$srv" "$REQ_COUNT" "$TIMEOUT"
    else
        measure_with_ping "$srv" "$REQ_COUNT" "$TIMEOUT"
    fi
}

# Вычисление скора
score_line() {
    local srv="$1" avg="$2" loss="$3" method="$4"
    avg=${avg:-9999}
    loss=${loss:-100}
    score=$(awk -v a="$avg" -v l="$loss" 'BEGIN { printf "%.2f", a * (1 + (l/100)*5) }')
    printf '%s|%s|%s|%s|%s' "$srv" "$avg" "$loss" "$method" "$score"
}

main() {
    # Проверка интернета
    check_internet

    read_servers
    echo "$(get_message 'testing' "${#servers[@]}" "$REQ_COUNT")"
    start_time=$(date +%s)
    results=()
    for s in "${servers[@]}"; do
        printf "$(get_message 'test' "$s")"
        line=$(measure_server "$s")
        IFS='|' read -r srv avg loss method <<<"$line"
        echo "$(get_message 'method_note' "$method")"
        scored=$(score_line "$srv" "$avg" "$loss" "$method")
        results+=("$scored")
        printf 'avg=%sms loss=%s%% method=%s score=%s\n' "$avg" "$loss" "$method" "$(echo "$scored" | awk -F'|' '{print $5}')"
        # Логирование
        echo "$(date): Server=$s avg=$avg ms loss=$loss% method=$method score=$(echo "$scored" | awk -F'|' '{print $5}')" >> "$LOG_FILE"
    done
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo
    echo "$(get_message 'total_time' "$elapsed")"
    echo
    echo "$(get_message 'top_results' "$TOP_N")"
    printf '%-3s %-16s %-8s %-8s %-8s\n' "#" "SERVER" "AVG(ms)" "LOSS(%)" "SCORE"
    IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t'|' -k5n))
    i=0
    for r in "${sorted[@]}"; do
        i=$((i + 1))
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
