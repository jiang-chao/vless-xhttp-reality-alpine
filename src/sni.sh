#!/usr/bin/env bash
# REALITY SNI candidates and latency-based selection.
# Candidates: large long-lived non-Cloudflare sites, root path 200 without
# redirect, TLS 1.3 + H2, served from global CDNs with US West / Japan edges.
# No .gov, bank or payment domains; no mainland China domains.

sni_candidates=(
    www.apple.com
    aws.amazon.com
    www.asus.com
    www.toyota.com
    www.lexus.com
    www.nikon.com
    www.ricoh.com
    www.yamaha.com
    www.micron.com
    www.westerndigital.com
    www.sandisk.com
    www.ea.com
    www.gm.com
    www.splunk.com
    www.paloaltonetworks.com
    www.mongodb.com
    www.dropbox.com
    www.bosch.com
)

sni_now_ms() {
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        local usec=${EPOCHREALTIME/[.,]/}
        echo $((10#$usec / 1000))
    else
        echo $(($(date +%s) * 1000))
    fi
}

sni_timeout() {
    local seconds=$1
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

# Print "<ms> <host>" when host accepts TCP 443 (and TLS 1.3 + H2 if openssl exists).
sni_probe() {
    local host=$1 best='' attempt start end ms tls_out
    for attempt in 1 2 3; do
        start=$(sni_now_ms)
        if sni_timeout 3 bash -c 'exec 3<>"/dev/tcp/$0/443"' "$host" 2>/dev/null; then
            end=$(sni_now_ms)
            ms=$((end - start))
            if [[ -z $best || $ms -lt $best ]]; then
                best=$ms
            fi
        elif [[ -z $best ]]; then
            return 1
        fi
    done
    [[ -n $best ]] || return 1
    if command -v openssl >/dev/null 2>&1; then
        tls_out=$(sni_timeout 6 openssl s_client -connect "$host:443" -servername "$host" -tls1_3 -alpn h2 </dev/null 2>&1) || true
        [[ $tls_out == *TLSv1.3* && $tls_out == *"ALPN protocol: h2"* ]] || return 1
    fi
    echo "$best $host"
}

# Probe all hosts in parallel; print "<ms> <host>" lines sorted by latency.
sni_rank() {
    local tmp host pids=()
    tmp=$(mktemp -d) || return 1
    for host in "$@"; do
        (sni_probe "$host" >"$tmp/$host" 2>/dev/null) &
        pids+=($!)
    done
    wait "${pids[@]}" 2>/dev/null || true
    cat "$tmp"/* 2>/dev/null | sort -n || true
    rm -rf "$tmp"
}

# Print the lowest-latency host; fall back to a random candidate if none respond.
# Set SNI_TEST=0 to skip the network test.
sni_select() {
    local hosts=("$@") ranked best
    ((${#hosts[@]})) || hosts=("${sni_candidates[@]}")
    if [[ ${SNI_TEST:-1} != 0 ]]; then
        echo "正在测试 ${#hosts[@]} 个 SNI 候选站点的延迟 ..." >&2
        ranked=$(sni_rank "${hosts[@]}")
        if [[ -n $ranked ]]; then
            IFS=" " read -r ms best <<<"$(head -n1 <<<"$ranked")"
            echo "已选择延迟最低的 SNI: $best (${ms} ms)" >&2
            echo "$best"
            return 0
        fi
        echo "所有候选站点测试均失败, 改用随机选择." >&2
    fi
    echo "${hosts[$((RANDOM % ${#hosts[@]}))]}"
}

sni_report() {
    local hosts=("$@") ranked line
    ((${#hosts[@]})) || hosts=("${sni_candidates[@]}")
    echo "测试 ${#hosts[@]} 个 SNI 候选站点 (TCP 443 延迟; 有 openssl 时同时校验 TLS 1.3 + H2) ..."
    ranked=$(sni_rank "${hosts[@]}")
    if [[ -z $ranked ]]; then
        echo "没有可用的候选站点, 请检查出口网络."
        return 1
    fi
    while read -r line; do
        echo "  ${line%% *} ms  ${line#* }"
    done <<<"$ranked"
    echo "建议使用: $(head -n1 <<<"$ranked" | cut -d' ' -f2)"
}