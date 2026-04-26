#!/usr/bin/env bash
set -euo pipefail

# DNS Benchmark Tool
# A modern replacement for Google's abandoned namebench project.
# Benchmarks DNS resolvers by measuring query latency and reliability.

VERSION="1.0.0"
RESOLVERS_FILE="/etc/namebench/resolvers.txt"
RESULTS_DIR="/results"
QUERIES=50
DOMAINS_FILE=""
PARALLEL=1
OUTPUT_FORMAT="text"

# Default test domains (mix of popular and less-cached domains)
DEFAULT_DOMAINS=(
    "google.com"
    "facebook.com"
    "youtube.com"
    "amazon.com"
    "wikipedia.org"
    "twitter.com"
    "reddit.com"
    "netflix.com"
    "github.com"
    "stackoverflow.com"
    "cloudflare.com"
    "apple.com"
    "microsoft.com"
    "nrk.no"
    "vg.no"
    "bbc.co.uk"
    "reuters.com"
    "arxiv.org"
    "kernel.org"
    "debian.org"
)

usage() {
    cat <<EOF
DNS Benchmark Tool v${VERSION}

Usage: benchmark [OPTIONS]

Options:
  -r, --resolvers FILE   Path to resolvers file (default: ${RESOLVERS_FILE})
  -q, --queries NUM      Number of queries per resolver (default: ${QUERIES})
  -d, --domains FILE     File with domains to query (one per line)
  -p, --parallel NUM     Parallel queries (default: ${PARALLEL})
  -o, --output DIR       Output directory (default: ${RESULTS_DIR})
  -f, --format FORMAT    Output format: text, csv, json (default: ${OUTPUT_FORMAT})
  -l, --list             List configured resolvers and exit
  -h, --help             Show this help message

Examples:
  benchmark                          Run with defaults
  benchmark -q 100 -f json           100 queries per resolver, JSON output
  benchmark -r /my/resolvers.txt     Use custom resolvers file
  benchmark -l                       List resolvers

EOF
}

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

check_dependencies() {
    local missing=()
    for cmd in dig bc; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
    fi
}

list_resolvers() {
    if [[ ! -f "$RESOLVERS_FILE" ]]; then
        error "Resolvers file not found: ${RESOLVERS_FILE}"
    fi
    echo "Configured DNS Resolvers:"
    echo "========================="
    while IFS=$' \t' read -r ip name; do
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        printf "  %-18s %s\n" "$ip" "${name:-unnamed}"
    done < "$RESOLVERS_FILE"
}

# Query a single domain against a resolver and return latency in ms
query_latency() {
    local resolver="$1"
    local domain="$2"
    local result

    result=$(dig "@${resolver}" "$domain" A +noall +stats +tries=1 +time=3 2>/dev/null \
        | grep "Query time:" \
        | awk '{print $4}')

    if [[ -n "$result" ]]; then
        echo "$result"
    else
        echo "timeout"
    fi
}

# Benchmark a single resolver
benchmark_resolver() {
    local ip="$1"
    local name="$2"
    local domains=("${@:3}")
    local total_ms=0
    local success=0
    local failures=0
    local min_ms=999999
    local max_ms=0
    local latencies=()

    for i in $(seq 1 "$QUERIES"); do
        # Pick a domain (cycle through the list)
        local idx=$(( (i - 1) % ${#domains[@]} ))
        local domain="${domains[$idx]}"

        local ms
        ms=$(query_latency "$ip" "$domain")

        if [[ "$ms" == "timeout" ]]; then
            (( failures++ )) || true
        else
            (( success++ )) || true
            total_ms=$(echo "$total_ms + $ms" | bc)
            latencies+=("$ms")
            if (( ms < min_ms )); then min_ms=$ms; fi
            if (( ms > max_ms )); then max_ms=$ms; fi
        fi
    done

    local avg_ms="N/A"
    local median_ms="N/A"
    local reliability="0.0"

    if (( success > 0 )); then
        avg_ms=$(echo "scale=1; $total_ms / $success" | bc)
        reliability=$(echo "scale=1; $success * 100 / $QUERIES" | bc)

        # Calculate median
        local sorted
        sorted=$(printf '%s\n' "${latencies[@]}" | sort -n)
        local mid=$(( success / 2 ))
        median_ms=$(echo "$sorted" | sed -n "$((mid + 1))p")
    fi

    if (( min_ms == 999999 )); then min_ms="N/A"; fi
    if (( max_ms == 0 && success == 0 )); then max_ms="N/A"; fi

    # Return results as tab-separated values
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$ip" "$name" "$avg_ms" "$median_ms" "$min_ms" "$max_ms" "$reliability" "$success/$QUERIES"
}

# Output results in text format
output_text() {
    local results_file="$1"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           DNS Benchmark Results                                 ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════════╣"
    printf "║ %-18s %-14s %6s %6s %6s %6s %7s %7s ║\n" \
        "Resolver" "Name" "Avg" "Med" "Min" "Max" "Rel%" "Ok"
    echo "╠══════════════════════════════════════════════════════════════════════════════════╣"

    # Sort by average latency (column 3), treating N/A as very high
    sort -t$'\t' -k3 -n "$results_file" | while IFS=$'\t' read -r ip name avg med min max rel ok; do
        printf "║ %-18s %-14s %6s %6s %6s %6s %6s%% %7s ║\n" \
            "$ip" "$name" "${avg}ms" "${med}ms" "${min}ms" "${max}ms" "$rel" "$ok"
    done

    echo "╚══════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Queries per resolver: ${QUERIES}"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}

# Output results in CSV format
output_csv() {
    local results_file="$1"
    echo "resolver_ip,name,avg_ms,median_ms,min_ms,max_ms,reliability_pct,success_ratio"
    while IFS=$'\t' read -r ip name avg med min max rel ok; do
        echo "${ip},${name},${avg},${med},${min},${max},${rel},${ok}"
    done < "$results_file"
}

# Output results in JSON format
output_json() {
    local results_file="$1"

    if command -v jq &>/dev/null; then
        local json_array="[]"
        while IFS=$'\t' read -r ip name avg med min max rel ok; do
            json_array=$(echo "$json_array" | jq \
                --arg ip "$ip" \
                --arg name "$name" \
                --arg avg "$avg" \
                --arg med "$med" \
                --arg min "$min" \
                --arg max "$max" \
                --arg rel "$rel" \
                --arg ok "$ok" \
                '. += [{"resolver": $ip, "name": $name, "avg_ms": $avg, "median_ms": $med, "min_ms": $min, "max_ms": $max, "reliability_pct": $rel, "queries": $ok}]')
        done < "$results_file"

        echo '{"version":"'"${VERSION}"'","timestamp":"'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'","queries_per_resolver":'"${QUERIES}"',"results":'"${json_array}"'}' | jq .
    else
        # Fallback without jq
        echo '{"version":"'"${VERSION}"'","timestamp":"'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'","queries_per_resolver":'"${QUERIES}"',"results":['
        local first=true
        while IFS=$'\t' read -r ip name avg med min max rel ok; do
            if [[ "$first" == "true" ]]; then first=false; else echo ","; fi
            printf '{"resolver":"%s","name":"%s","avg_ms":"%s","median_ms":"%s","min_ms":"%s","max_ms":"%s","reliability_pct":"%s","queries":"%s"}' \
                "$ip" "$name" "$avg" "$med" "$min" "$max" "$rel" "$ok"
        done < "$results_file"
        echo ']}'
    fi
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--resolvers) RESOLVERS_FILE="$2"; shift 2 ;;
            -q|--queries)   QUERIES="$2"; shift 2 ;;
            -d|--domains)   DOMAINS_FILE="$2"; shift 2 ;;
            -p|--parallel)  PARALLEL="$2"; shift 2 ;;
            -o|--output)    RESULTS_DIR="$2"; shift 2 ;;
            -f|--format)    OUTPUT_FORMAT="$2"; shift 2 ;;
            -l|--list)      list_resolvers; exit 0 ;;
            -h|--help)      usage; exit 0 ;;
            *)              error "Unknown option: $1" ;;
        esac
    done

    check_dependencies

    if [[ ! -f "$RESOLVERS_FILE" ]]; then
        error "Resolvers file not found: ${RESOLVERS_FILE}"
    fi

    mkdir -p "$RESULTS_DIR"

    # Load domains
    local domains=()
    if [[ -n "$DOMAINS_FILE" && -f "$DOMAINS_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            domains+=("$line")
        done < "$DOMAINS_FILE"
    else
        domains=("${DEFAULT_DOMAINS[@]}")
    fi

    if [[ ${#domains[@]} -eq 0 ]]; then
        error "No domains to test"
    fi

    # Load resolvers
    local resolver_ips=()
    local resolver_names=()
    while IFS=$' \t' read -r ip name; do
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        resolver_ips+=("$ip")
        resolver_names+=("${name:-unnamed}")
    done < "$RESOLVERS_FILE"

    if [[ ${#resolver_ips[@]} -eq 0 ]]; then
        error "No resolvers found in ${RESOLVERS_FILE}"
    fi

    local total=${#resolver_ips[@]}
    log "Starting DNS benchmark: ${total} resolvers, ${QUERIES} queries each, ${#domains[@]} test domains"
    log ""

    local results_file
    results_file=$(mktemp)

    for idx in "${!resolver_ips[@]}"; do
        local ip="${resolver_ips[$idx]}"
        local name="${resolver_names[$idx]}"
        local num=$((idx + 1))

        log "[${num}/${total}] Benchmarking ${name} (${ip})..."
        benchmark_resolver "$ip" "$name" "${domains[@]}" >> "$results_file"
    done

    log ""
    log "Benchmark complete."

    # Output results
    case "$OUTPUT_FORMAT" in
        text) output_text "$results_file" ;;
        csv)  output_csv "$results_file" ;;
        json) output_json "$results_file" ;;
        *)    error "Unknown format: ${OUTPUT_FORMAT}" ;;
    esac

    # Save results to file
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local output_file="${RESULTS_DIR}/benchmark_${timestamp}.${OUTPUT_FORMAT}"

    case "$OUTPUT_FORMAT" in
        text) output_text "$results_file" > "$output_file" ;;
        csv)  output_csv "$results_file" > "$output_file" ;;
        json) output_json "$results_file" > "$output_file" ;;
    esac

    log "Results saved to: ${output_file}"

    rm -f "$results_file"
}

main "$@"
