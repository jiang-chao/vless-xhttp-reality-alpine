#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Optional VLESS + XHTTP + REALITY service for Alpine/NAT deployments.

set -Eeuo pipefail
IFS=$'\n\t'

readonly XRAY_DIR='/etc/xray'
readonly XRAY_CONF_DIR="${XRAY_DIR}/profiles"
readonly XRAY_CONFIG="${XRAY_DIR}/config.json"
readonly MANAGED_MARKER="${XRAY_DIR}/.sing-box-xhttp-managed"
readonly XRAY_BIN='/usr/local/bin/xray'
readonly SERVICE='xray-xhttp'
readonly SERVICE_FILE="/etc/init.d/${SERVICE}"
readonly SYSTEMD_FILE="/etc/systemd/system/${SERVICE}.service"
readonly XRAY_RELEASE_API='https://api.github.com/repos/XTLS/Xray-core/releases/latest'

err() { printf '错误：%s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
need_root() { [[ ${EUID} -eq 0 ]] || err '请使用 root 运行。'; }
valid_port() { [[ ${1:-} =~ ^[0-9]{1,5}$ ]] && (( 10#$1 > 0 && 10#$1 < 65536 )); }
normalize_port() { printf '%s' "$((10#$1))"; }
valid_host() { [[ ${1:-} =~ ^[A-Za-z0-9.-]+$ && $1 != *..* && $1 != .* && $1 != *. ]]; }
valid_address() { valid_host "$1" || [[ ${1:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_path() { [[ ${1:-} == /* && $1 != *' '* && $1 != *$'\t'* && $1 != *$'\r'* && $1 != *$'\n'* ]]; }
urlencode() { jq -rn --arg value "$1" '$value|@uri'; }

need_alpine_or_supported_linux() {
  if [[ -f /etc/alpine-release ]]; then
    local alpine_version alpine_major alpine_minor
    alpine_version="$(cat /etc/alpine-release)"
    alpine_major="${alpine_version%%.*}"
    alpine_minor="${alpine_version#*.}"
    alpine_minor="${alpine_minor%%.*}"
    [[ $alpine_major =~ ^[0-9]+$ && $alpine_minor =~ ^[0-9]+$ ]] || err "无法识别 Alpine 版本：${alpine_version}"
    (( alpine_major > 3 || (alpine_major == 3 && alpine_minor >= 21) )) || err 'XHTTP 扩展要求 Alpine 3.21 或更新版本。'
    command -v rc-service >/dev/null 2>&1 || err 'Alpine 需要 OpenRC（rc-service）。'
  elif command -v systemctl >/dev/null 2>&1; then
    :
  else
    err 'XHTTP 扩展需要 Alpine/OpenRC 或 systemd。'
  fi
}

install_dependencies() {
  if [[ -f /etc/alpine-release ]]; then
    apk add --no-cache bash ca-certificates curl gcompat iproute2 jq openssl tar unzip
    update-ca-certificates >/dev/null 2>&1 || true
  else
    command -v jq >/dev/null 2>&1 || err '请先安装 jq。'
    command -v curl >/dev/null 2>&1 || err '请先安装 curl。'
    command -v unzip >/dev/null 2>&1 || err '请先安装 unzip。'
    command -v openssl >/dev/null 2>&1 || err '请先安装 openssl。'
  fi
}

arch_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s' 'Xray-linux-64.zip' ;;
    aarch64|arm64) printf '%s' 'Xray-linux-arm64-v8a.zip' ;;
    *) err "不支持的 CPU 架构：$(uname -m)" ;;
  esac
}

install_xray() {
  local release asset url expected actual tmpdir
  release="$(curl -fsSL "$XRAY_RELEASE_API")"
  asset="$(arch_asset)"
  url="$(jq -r --arg asset "$asset" '.assets[]|select(.name==$asset)|.browser_download_url' <<<"$release")"
  [[ -n $url && $url != null ]] || err "Xray 最新发行版中找不到 ${asset}。"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf -- "$tmpdir"; trap - RETURN' RETURN
  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmpdir/xray.zip"
  expected="$(curl -fsSL --proto '=https' --tlsv1.2 "${url}.dgst" | awk -F'= ' '/SHA2-256/ {print $2; exit}')"
  actual="$(sha256sum "$tmpdir/xray.zip" | awk '{print $1}')"
  [[ -n $expected && $actual == "$expected" ]] || err 'Xray SHA-256 校验失败。'
  unzip -qo "$tmpdir/xray.zip" -d "$tmpdir/unpacked"
  [[ -x "$tmpdir/unpacked/xray" ]] || err 'Xray 发布包中缺少可执行文件。'
  install -Dm755 "$tmpdir/unpacked/xray" "$XRAY_BIN"
  mkdir -p "$XRAY_DIR"
  [[ ! -f "$tmpdir/unpacked/geoip.dat" ]] || install -m644 "$tmpdir/unpacked/geoip.dat" "$XRAY_DIR/geoip.dat"
  [[ ! -f "$tmpdir/unpacked/geosite.dat" ]] || install -m644 "$tmpdir/unpacked/geosite.dat" "$XRAY_DIR/geosite.dat"
  info "已安装 $($XRAY_BIN version | head -n 1)"
}

ensure_xray() {
  if [[ -x $XRAY_BIN ]]; then
    "$XRAY_BIN" x25519 >/dev/null 2>&1 || err "发现无法生成 REALITY 密钥的 ${XRAY_BIN}。"
  else
    install_xray
  fi
}

write_aggregate_config() {
  local next="${XRAY_DIR}/.config.$$.json" profile
  local profiles=()
  shopt -s nullglob
  profiles=("${XRAY_CONF_DIR}"/*.json)
  shopt -u nullglob
  if ((${#profiles[@]} == 0)); then
    rm -f "$next"
    [[ ! -f $XRAY_CONFIG ]] || rm -f "$XRAY_CONFIG"
    return 0
  fi
  jq -s '{log:{loglevel:"warning"},inbounds:[.[]|.inbounds[]],outbounds:[{protocol:"freedom",tag:"direct"},{protocol:"blackhole",tag:"block"}]}' "${profiles[@]}" >"$next"
  chmod 600 "$next"
  if ! "$XRAY_BIN" run -test -config "$next" >/dev/null; then
    rm -f "$next"
    return 1
  fi
  mv -f "$next" "$XRAY_CONFIG"
}

service_action() {
  local action="$1"
  if [[ -f /etc/alpine-release ]]; then
    rc-service "$SERVICE" "$action"
  else
    systemctl "$action" "$SERVICE"
  fi
}

ensure_service() {
  if [[ -f /etc/alpine-release ]]; then
    install -d -m 755 /var/log/xray
    cat >"$SERVICE_FILE" <<'EOF'
#!/sbin/openrc-run
name="Xray VLESS XHTTP REALITY"
description="Xray VLESS + XHTTP + REALITY"
command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"
command_background="yes"
supervisor=supervise-daemon
pidfile="/run/xray-xhttp.pid"
output_log="/var/log/xray/xhttp-access.log"
error_log="/var/log/xray/xhttp-error.log"

depend() {
    need net
    after firewall
}
EOF
    chmod 755 "$SERVICE_FILE"
    rc-update add "$SERVICE" default >/dev/null
  else
    cat >"$SYSTEMD_FILE" <<EOF
[Unit]
Description=Xray VLESS XHTTP REALITY service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$XRAY_BIN run -config $XRAY_CONFIG
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE" >/dev/null
  fi
}

ask_value() {
  local prompt="$1" default="$2" answer
  read -r -p "$prompt [$default]: " answer
  printf '%s' "${answer:-$default}"
}

detect_host() { curl -4fsS --max-time 8 https://api64.ipify.org 2>/dev/null || printf '%s' 'YOUR_PUBLIC_IP_OR_DOMAIN'; }

add_profile() {
  need_root
  need_alpine_or_supported_linux
  install_dependencies
  local port="${1:-}" host="${2:-}" sni="${3:-}" path="${4:-}" public_port="${5:-}"
  [[ -n $port ]] || port="$(ask_value '监听 TCP 端口（NAT 需映射此端口）' '443')"
  valid_port "$port" || err '端口必须是 1–65535 的整数。'
  port=$((10#$port))
  [[ -n $host ]] || host="$(ask_value '分享链接公网地址（NAT 填宿主机公网 IP/域名）' "$(detect_host)")"
  valid_address "$host" || err '公网地址须为域名或 IPv4 地址。'
  [[ -n $public_port ]] || public_port="$(ask_value 'NAT 公网映射端口（非 NAT 填与监听端口相同值）' "$port")"
  valid_port "$public_port" || err '公网端口必须是 1–65535 的整数。'
  public_port=$((10#$public_port))
  [[ -n $sni ]] || sni="$(ask_value 'REALITY SNI/目标域名' 'www.cloudflare.com')"
  valid_host "$sni" || err 'SNI 须为有效域名。'
  [[ -n $path ]] || path="$(ask_value 'XHTTP 路径' "/xhttp-$(openssl rand -hex 8)")"
  valid_path "$path" || err 'XHTTP 路径必须以 / 开头且不能包含空格。'
  [[ ! -e "${XRAY_CONF_DIR}/${port}.json" ]] || err "端口 ${port} 已有 XHTTP 配置。"
  if command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :${port}" | grep -q .; then
    err "容器 TCP 端口 ${port} 已被占用；请使用空闲端口或调整现有服务。"
  fi
  if [[ -d /etc/sing-box/conf ]]; then
    local singbox_profile
    shopt -s nullglob
    local singbox_profiles=(/etc/sing-box/conf/*.json)
    shopt -u nullglob
    for singbox_profile in "${singbox_profiles[@]}"; do
      if jq -e --argjson port "$port" 'any(.inbounds[]?; .listen_port == $port)' "$singbox_profile" >/dev/null; then
        err "容器 TCP 端口 ${port} 已被 sing-box 配置占用（${singbox_profile}）。"
      fi
    done
  fi

  if [[ -f $XRAY_CONFIG && ! -f $MANAGED_MARKER ]]; then
    err "检测到既有 ${XRAY_CONFIG}，为避免覆盖非本扩展配置，已停止。"
  fi
  if [[ -e $SERVICE_FILE && ! -f $MANAGED_MARKER ]] || [[ -e $SYSTEMD_FILE && ! -f $MANAGED_MARKER ]]; then
    err "检测到既有 ${SERVICE} 服务文件，为避免覆盖已停止。"
  fi
  ensure_xray
  install -d -m 700 "$XRAY_CONF_DIR"
  local pair private_key public_key uuid short_id profile
  pair="$("$XRAY_BIN" x25519)"
  private_key="$(awk -F: '/^[[:space:]]*[Pp]rivate[ _-]*[Kk]ey[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' <<<"$pair" | tr -d '\r')"
  public_key="$(awk -F: '/^[[:space:]]*[Pp]assword([[:space:]]*\([Pp]ublic[Kk]ey\))?[[:space:]]*:/ || /^[[:space:]]*[Pp]ublic[ _-]*[Kk]ey[[:space:]]*:/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' <<<"$pair" | tr -d '\r')"
  [[ -n $private_key && -n $public_key ]] || err '无法解析 Xray REALITY 密钥。'
  uuid="$("$XRAY_BIN" uuid)"
  short_id="$(openssl rand -hex 8)"
  profile="${XRAY_CONF_DIR}/${port}.json"
  umask 077
  jq -n --argjson port "$port" --argjson public_port "$public_port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private_key" --arg pbk "$public_key" --arg sid "$short_id" --arg path "$path" \
    '{xhttpPublicKey:$pbk,publicPort:$public_port,inbounds:[{tag:("vless-xhttp-"+($port|tostring)),listen:"0.0.0.0",port:$port,protocol:"vless",settings:{clients:[{id:$uuid,email:("xhttp-"+($port|tostring))}],decryption:"none"},streamSettings:{network:"xhttp",security:"reality",realitySettings:{show:false,dest:($sni+":443"),xver:0,serverNames:[$sni],privateKey:$private,shortIds:[$sid]},xhttpSettings:{path:$path,mode:"auto"}}}]}' >"$profile"
  if ! write_aggregate_config; then
    rm -f "$profile"
    err 'Xray 配置测试失败；新增配置未保留。'
  fi
  install -m 600 /dev/null "$MANAGED_MARKER"
  ensure_service
  if ! service_action restart 2>/dev/null && ! service_action start; then
    rm -f "$profile"
    write_aggregate_config || true
    service_action restart >/dev/null 2>&1 || service_action start >/dev/null 2>&1 || true
    err 'Xray 服务未能启动，已回滚本次 XHTTP 配置。请检查端口冲突和服务日志。'
  fi
  printf '\nXHTTP 配置已添加。分享链接：\n'
  share_profile "$public_port" "$host" "$sni" "$uuid" "$public_key" "$short_id" "$path"
  printf '\nNAT 提醒：请将宿主机 TCP %s 转发到本 LXC 的 TCP %s。\n' "$public_port" "$port"
}

share_profile() {
  local port="$1" host="$2" sni="$3" uuid="$4" pbk="$5" sid="$6" path="$7"
  printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s&mode=auto#VLESS-XHTTP-REALITY-%s\n' \
    "$uuid" "$host" "$port" "$(urlencode "$sni")" "$(urlencode "$pbk")" "$sid" "$(urlencode "$path")" "$port"
}

profile_link() {
  local port="$1" profile host sni uuid pbk sid path pair public_port
  valid_port "$port" || err '端口必须是 1–65535 的整数。'
  port="$(normalize_port "$port")"
  profile="$XRAY_CONF_DIR/$port.json"
  [[ -f $profile ]] || err "未找到 XHTTP 端口 ${port}。"
  host="${2:-$(detect_host)}"
  valid_address "$host" || err '公网地址须为域名或 IPv4 地址。'
  public_port="$(jq -r '.publicPort // .inbounds[0].port' "$profile")"
  pair="$(jq -r '.inbounds[0] as $i | [$i.streamSettings.realitySettings.serverNames[0],$i.settings.clients[0].id,$i.streamSettings.realitySettings.shortIds[0],$i.streamSettings.xhttpSettings.path] | @tsv' "$profile")"
  IFS=$'\t' read -r sni uuid sid path <<<"$pair"
  pbk="$(jq -r '.xhttpPublicKey' "$profile")"
  share_profile "$public_port" "$host" "$sni" "$uuid" "$pbk" "$sid" "$path"
}

show_profile() {
  local port="$1" host="${2:-}" profile public_port sni path uuid
  valid_port "$port" || err '端口必须是 1–65535 的整数。'
  port="$(normalize_port "$port")"
  host="${host:-$(detect_host)}"
  profile="$XRAY_CONF_DIR/$port.json"
  [[ -f $profile ]] || err "未找到 XHTTP 端口 ${port}。"
  public_port="$(jq -r '.publicPort // .inbounds[0].port' "$profile")"
  sni="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$profile")"
  path="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "$profile")"
  uuid="$(jq -r '.inbounds[0].settings.clients[0].id' "$profile")"
  printf '%s\n' "------------- XHTTP-${port}.json -------------" \
    '协议 (protocol)       = vless' \
    "地址 (address)        = ${host}" \
    "监听端口 (listen)     = ${port}" \
    "公网端口 (NAT)        = ${public_port}" \
    "用户ID (id)           = ${uuid}" \
    '传输协议 (network)    = xhttp' \
    '传输层安全 (TLS)      = reality' \
    "SNI (serverName)      = ${sni}" \
    "路径 (path)           = ${path}" \
    '------------- 链接 (URL) -------------'
  profile_link "$port" "$host"
}

edit_profile() {
  need_root
  need_alpine_or_supported_linux
  install_dependencies
  local old_port="$1" old_profile old_backup new_port public_port sni path current_public current_sni current_path
  valid_port "$old_port" || err '用法：sing-box xhttp edit PORT [NEW_PORT [PUBLIC_PORT [SNI [PATH]]]]'
  old_port="$(normalize_port "$old_port")"
  old_profile="$XRAY_CONF_DIR/$old_port.json"
  [[ -f $old_profile ]] || err "未找到 XHTTP 端口 ${old_port}。"
  current_public="$(jq -r '.publicPort // .inbounds[0].port' "$old_profile")"
  current_sni="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$old_profile")"
  current_path="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path' "$old_profile")"
  new_port="${2:-$(ask_value '新的容器监听 TCP 端口' "$old_port")}"
  public_port="${3:-$(ask_value '新的 NAT 公网映射端口' "$current_public")}"
  sni="${4:-$(ask_value '新的 REALITY SNI/目标域名' "$current_sni")}"
  path="${5:-$(ask_value '新的 XHTTP 路径' "$current_path")}"
  valid_port "$new_port" || err '监听端口必须是 1–65535 的整数。'
  valid_port "$public_port" || err '公网端口必须是 1–65535 的整数。'
  new_port="$(normalize_port "$new_port")"
  public_port="$(normalize_port "$public_port")"
  valid_host "$sni" || err 'SNI 须为有效域名。'
  valid_path "$path" || err 'XHTTP 路径必须以 / 开头且不能包含空格。'
  [[ $new_port == "$old_port" || ! -e "$XRAY_CONF_DIR/$new_port.json" ]] || err "端口 ${new_port} 已有 XHTTP 配置。"
  if [[ $new_port != "$old_port" ]] && command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :${new_port}" | grep -q .; then
    err "容器 TCP 端口 ${new_port} 已被占用。"
  fi
  if [[ -d /etc/sing-box/conf ]]; then
    local singbox_profile
    shopt -s nullglob
    local singbox_profiles=(/etc/sing-box/conf/*.json)
    shopt -u nullglob
    for singbox_profile in "${singbox_profiles[@]}"; do
      if jq -e --argjson port "$new_port" 'any(.inbounds[]?; .listen_port == $port)' "$singbox_profile" >/dev/null; then
        err "容器 TCP 端口 ${new_port} 已被 sing-box 配置占用（${singbox_profile}）。"
      fi
    done
  fi

  old_backup="$XRAY_CONF_DIR/.${old_port}.json.$$"
  local new_profile="$XRAY_CONF_DIR/$new_port.json" staged="$XRAY_CONF_DIR/.${new_port}.json.$$.tmp"
  jq --argjson port "$new_port" --argjson public_port "$public_port" --arg sni "$sni" --arg path "$path" \
    '.publicPort=$public_port | .inbounds[0].port=$port | .inbounds[0].streamSettings.realitySettings.dest=($sni+":443") | .inbounds[0].streamSettings.realitySettings.serverNames=[$sni] | .inbounds[0].streamSettings.xhttpSettings.path=$path' \
    "$old_profile" >"$staged"
  chmod 600 "$staged"
  mv "$old_profile" "$old_backup"
  mv "$staged" "$new_profile"
  if ! write_aggregate_config; then
    rm -f "$new_profile"
    mv "$old_backup" "$old_profile"
    err 'Xray 配置测试失败；修改已取消，原配置已恢复。'
  fi
  if ! service_action restart; then
    rm -f "$new_profile"
    mv "$old_backup" "$old_profile"
    write_aggregate_config || true
    service_action restart >/dev/null 2>&1 || true
    err 'Xray 服务重启失败；修改已取消，原配置已恢复。'
  fi
  rm -f "$old_backup"
  info "已更新 XHTTP 配置：${old_port} -> ${new_port}。"
  show_profile "$new_port"
}

list_profiles() {
  local profile port host
  shopt -s nullglob
  local profiles=("$XRAY_CONF_DIR"/*.json)
  shopt -u nullglob
  ((${#profiles[@]})) || { info '当前没有 XHTTP 配置。'; return; }
  host="${1:-$(detect_host)}"
  for profile in "${profiles[@]}"; do
    port="$(basename "$profile" .json)"
    printf '\n端口：%s\n' "$port"
    profile_link "$port" "$host"
  done
}

delete_profile() {
  need_root
  local port="${1:-}"
  valid_port "$port" || err '用法：sing-box xhttp del PORT'
  port="$(normalize_port "$port")"
  [[ -f "${XRAY_CONF_DIR}/${port}.json" ]] || err "未找到 XHTTP 端口 ${port}。"
  local profile="${XRAY_CONF_DIR}/${port}.json" backup="${XRAY_CONF_DIR}/.${port}.json.$$"
  mv "$profile" "$backup"
  if ! write_aggregate_config; then
    mv "$backup" "$profile"
    err 'Xray 配置测试失败；删除已取消，原配置已恢复。'
  fi
  shopt -s nullglob
  local remaining=("$XRAY_CONF_DIR"/*.json)
  shopt -u nullglob
  if ((${#remaining[@]})); then
    if ! service_action restart; then
      mv "$backup" "$profile"
      write_aggregate_config || true
      service_action restart >/dev/null 2>&1 || true
      err 'Xray 服务重启失败；删除已取消，原配置已恢复。'
    fi
  else
    if ! service_action stop >/dev/null 2>&1; then
      if service_action status >/dev/null 2>&1; then
        mv "$backup" "$profile"
        write_aggregate_config || true
        service_action restart >/dev/null 2>&1 || true
        err 'Xray 服务停止失败；删除已取消，原配置已恢复。'
      fi
    fi
    if [[ -f /etc/alpine-release ]]; then
      rc-update del "$SERVICE" default >/dev/null 2>&1 || true
      rm -f "$SERVICE_FILE"
    else
      systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
      rm -f "$SYSTEMD_FILE"
      systemctl daemon-reload
    fi
    rm -f "$MANAGED_MARKER"
  fi
  rm -f "$backup"
  info "已删除 XHTTP 端口 ${port}。"
}

main() {
  local action="${1:-help}"
  shift || true
  case "${action,,}" in
    add|install) add_profile "$@" ;;
    list|ls) list_profiles "$@" ;;
    info|url)
      if [[ -n ${1:-} ]]; then show_profile "$1" "${2:-}"; else list_profiles "${2:-}"; fi
      ;;
    edit|change) edit_profile "${@}" ;;
    del|delete|remove) delete_profile "${1:-}" ;;
    restart|start|stop|status)
      need_root
      service_action "$action"
      ;;
    update)
      need_root
      need_alpine_or_supported_linux
      install_dependencies
      [[ -x $XRAY_BIN ]] || err 'Xray 尚未安装。'
      [[ -f $XRAY_CONFIG ]] || err '没有可更新的 XHTTP 配置。'
      service_action stop || true
      install_xray
      "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >/dev/null
      service_action start
      ;;
    help|-h|--help)
      cat <<'EOF'
用法：
  sing-box xhttp add [PORT [PUBLIC_HOST [SNI [PATH [PUBLIC_PORT]]]]]  添加 VLESS + XHTTP + REALITY
  sing-box xhttp list [PUBLIC_HOST]                     列出配置与分享链接
  sing-box xhttp info [PORT [PUBLIC_HOST]]              显示分享链接
  sing-box xhttp edit PORT [NEW_PORT [PUBLIC_PORT [SNI [PATH]]]] 修改配置
  sing-box xhttp del PORT                               删除配置
  sing-box xhttp status|start|stop|restart              管理 Xray XHTTP 服务
  sing-box xhttp update                                 更新 Xray 内核

快捷方式：sing-box add xhttp [PORT [PUBLIC_HOST [SNI [PATH [PUBLIC_PORT]]]]]
EOF
      ;;
    *) err "未知 XHTTP 命令：${action}。运行 sing-box xhttp help 查看用法。" ;;
  esac
}

main "$@"
