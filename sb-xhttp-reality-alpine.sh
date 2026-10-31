#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# sb-xhttp-reality-alpine
# A small, Alpine/OpenRC-focused installer inspired by 233boy/sing-box.
# It is an independent implementation for one use case only:
# VLESS + XHTTP + REALITY using the official Xray-core binary.

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_NAME='sb-xhttp-reality'
readonly XRAY_DIR='/etc/xray'
readonly CONFIG_FILE="${XRAY_DIR}/config.json"
readonly STATE_FILE="${XRAY_DIR}/vless-xhttp-reality.env"
readonly XRAY_BIN='/usr/local/bin/xray'
readonly SB_BIN='/usr/local/bin/sb'
readonly SERVICE='xray-vless'
readonly INIT_FILE="/etc/init.d/${SERVICE}"
readonly REPO_API='https://api.github.com/repos/XTLS/Xray-core/releases/latest'

die() { printf '\033[31m错误：%s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
need_root() { [ "${EUID}" -eq 0 ] || die '请使用 root 运行。'; }
need_alpine() { [ -f /etc/alpine-release ] || die '本脚本仅面向 Alpine Linux。'; }
need_openrc() { command -v rc-service >/dev/null 2>&1 || die '未检测到 OpenRC（rc-service）。请在带 OpenRC 的 Alpine LXC 中运行。'; }

ensure_dependencies() {
  info '安装所需组件…'
  apk update
  apk add --no-cache bash ca-certificates curl gcompat jq openssl unzip
  update-ca-certificates
}

arch_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' 'Xray-linux-64.zip' ;;
    aarch64|arm64) printf '%s\n' 'Xray-linux-arm64-v8a.zip' ;;
    *) die "不支持的 CPU 架构：$(uname -m)（仅支持 x86_64 与 aarch64）。" ;;
  esac
}

download_xray() {
  local tmpdir release asset expected actual url dgst_url
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  release="$(curl -fsSL "$REPO_API")"
  asset="$(arch_asset)"
  url="$(jq -r --arg n "$asset" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$release")"
  [ -n "$url" ] && [ "$url" != 'null' ] || die "最新 Xray 版本中没有 ${asset}。"
  dgst_url="${url}.dgst"
  info '下载并校验官方 Xray 内核…'
  curl --fail --location --proto '=https' --tlsv1.2 -o "$tmpdir/xray.zip" "$url"
  expected="$(curl --fail --location --proto '=https' --tlsv1.2 "$dgst_url" | awk -F'= ' '/SHA2-256/ {print $2; exit}')"
  [ -n "$expected" ] || die '无法读取 Xray 发布校验和。'
  actual="$(sha256sum "$tmpdir/xray.zip" | awk '{print $1}')"
  [ "$expected" = "$actual" ] || die 'Xray 下载文件的 SHA-256 校验失败，已中止。'
  unzip -qo "$tmpdir/xray.zip" -d "$tmpdir/xray"
  [ -x "$tmpdir/xray/xray" ] || die '下载包中没有 xray 可执行文件。'
  install -Dm755 "$tmpdir/xray/xray" "$XRAY_BIN"
  [ -f "$tmpdir/xray/geoip.dat" ] && install -Dm644 "$tmpdir/xray/geoip.dat" "${XRAY_DIR}/geoip.dat"
  [ -f "$tmpdir/xray/geosite.dat" ] && install -Dm644 "$tmpdir/xray/geosite.dat" "${XRAY_DIR}/geosite.dat"
  ok "已安装 $($XRAY_BIN version | head -n 1)"
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" != *..* ]] && [[ "$1" != .* ]] && [[ "$1" != *. ]]; }
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

ask_default() {
  local prompt="$1" default="$2" answer
  read -r -p "${prompt} [${default}]: " answer
  printf '%s\n' "${answer:-$default}"
}

ask_password() {
  local first second
  while :; do
    read -r -s -p '请输入 SOCKS5 密码（输入不回显）: ' first
    printf '\n' >&2
    [ -n "$first" ] || { warn '密码不能为空。'; continue; }
    read -r -s -p '请再次输入密码确认: ' second
    printf '\n' >&2
    if [ "$first" = "$second" ]; then
      printf '%s' "$first"
      return 0
    fi
    warn '两次密码不一致，请重新输入。'
  done
}

make_temp_file() {
  local suffix="${1:-.tmp}" candidate attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    candidate="${XRAY_DIR}/.sb-$$-${RANDOM}${suffix}"
    # noclobber makes file creation exclusive, even if another invocation races.
    if (set -o noclobber; : >"$candidate") 2>/dev/null; then
      chmod 600 "$candidate" || { rm -f "$candidate"; die '无法设置临时文件权限。'; }
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  die '无法安全创建临时文件。'
}

detect_public_host() {
  local host
  host="$(curl -4fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  [ -n "$host" ] || host='YOUR_PUBLIC_IP_OR_DOMAIN'
  printf '%s\n' "$host"
}

make_keys() {
  local pair
  pair="$($XRAY_BIN x25519)"
  PRIVATE_KEY="$(awk -F: '
    /^[[:space:]]*[Pp]rivate[ _-]*[Kk]ey[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); print; exit
    }
  ' <<<"$pair" | tr -d '\r')"
  PUBLIC_KEY="$(awk -F: '
    /^[[:space:]]*[Pp]assword([[:space:]]*\([Pp]ublic[Kk]ey\))?[[:space:]]*:/ || /^[[:space:]]*[Pp]ublic[ _-]*[Kk]ey[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); print; exit
    }
  ' <<<"$pair" | tr -d '\r')"
  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    local labels
    labels="$(awk -F: '/^[[:space:]]*[[:alnum:] _()-]+:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}' <<<"$pair" | paste -sd ', ' -)"
    die "无法解析 REALITY 密钥字段（检测到字段：${labels:-无}）。请确认 Xray x25519 输出格式。"
  fi
}

write_config() {
  install -d -m 700 "$XRAY_DIR"
  umask 077
  jq -n \
    --argjson port "$PORT" \
    --arg uuid "$UUID" \
    --arg sni "$SNI" \
    --arg private_key "$PRIVATE_KEY" \
    --arg sid "$SHORT_ID" \
    --arg path "$PATH_VALUE" \
    '{log:{loglevel:"warning"},inbounds:[{listen:"::",port:$port,protocol:"vless",settings:{clients:[{id:$uuid,email:"default",flow:""}],decryption:"none"},streamSettings:{network:"xhttp",security:"reality",realitySettings:{show:false,dest:($sni+":443"),xver:0,serverNames:[$sni],privateKey:$private_key,shortIds:[$sid]},xhttpSettings:{path:$path,mode:"auto"}}}],outbounds:[{protocol:"freedom",tag:"direct"},{protocol:"blackhole",tag:"block"}]}' \
    >"$CONFIG_FILE"
  "$XRAY_BIN" run -test -config "$CONFIG_FILE" >/dev/null
}

write_state() {
  umask 077
  {
    printf 'PORT=%q\n' "$PORT"
    printf 'UUID=%q\n' "$UUID"
    printf 'SNI=%q\n' "$SNI"
    printf 'PRIVATE_KEY=%q\n' "$PRIVATE_KEY"
    printf 'PUBLIC_KEY=%q\n' "$PUBLIC_KEY"
    printf 'SHORT_ID=%q\n' "$SHORT_ID"
    printf 'PATH_VALUE=%q\n' "$PATH_VALUE"
    printf 'PUBLIC_HOST=%q\n' "$PUBLIC_HOST"
  } >"$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

write_openrc_service() {
  install -d -m 755 /var/log/xray
  cat >"$INIT_FILE" <<'EOF'
#!/sbin/openrc-run
name="Xray VLESS XHTTP REALITY"
description="Xray VLESS + XHTTP + REALITY"
command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"
command_background="yes"
pidfile="/run/xray-vless.pid"
output_log="/var/log/xray/access.log"
error_log="/var/log/xray/error.log"

depend() {
    need net
    after firewall
}
EOF
  chmod 755 "$INIT_FILE"
}

install_manager() {
  install -Dm755 "$0" "$SB_BIN"
}

load_state() {
  [ -f "$STATE_FILE" ] || die '未找到配置。请先运行：sb install'
  # State is written only by this root-owned script with shell-escaped values.
  # shellcheck disable=SC1090
  . "$STATE_FILE"
}

share_link() {
  load_state
  local path_encoded name
  path_encoded="$(urlencode "$PATH_VALUE")"
  name="$(urlencode 'VLESS-XHTTP-REALITY')"
  printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s&mode=auto#%s\n' \
    "$UUID" "$PUBLIC_HOST" "$PORT" "$SNI" "$PUBLIC_KEY" "$SHORT_ID" "$path_encoded" "$name"
}

show_info() {
  load_state
  printf '\n%s\n' 'VLESS + XHTTP + REALITY'
  printf '公开地址: %s:%s\nSNI/伪装站: %s\nXHTTP 路径: %s\n\n分享链接：\n' "$PUBLIC_HOST" "$PORT" "$SNI" "$PATH_VALUE"
  share_link
  socks5_list
  printf '\n提示：NAT 宿主机须将 TCP %s 转发到此 LXC 的同一端口。\n' "$PORT"
}

apply_config_change() {
  local next_config="$1" backup test_output
  backup="$(make_temp_file .backup)"
  cp -p "$CONFIG_FILE" "$backup"
  if ! test_output="$("$XRAY_BIN" run -test -config "$next_config" 2>&1)"; then
    [ -n "$test_output" ] && printf '%s\n' "$test_output" >&2
    rm -f "$next_config" "$backup"
    die '配置测试失败，原配置未更改。'
  fi
  if ! mv -f "$next_config" "$CONFIG_FILE"; then
    rm -f "$backup"
    die '无法替换配置，原配置未更改。'
  fi
  if ! rc-service "$SERVICE" restart; then
    cp -p "$backup" "$CONFIG_FILE"
    rc-service "$SERVICE" restart >/dev/null 2>&1 || true
    rm -f "$backup"
    die '服务重启失败，已恢复原配置。'
  fi
  rm -f "$backup"
}

socks5_list() {
  [ -f "$CONFIG_FILE" ] || return 0
  local found=0 tag port user pass uri_host
  while IFS=$'\t' read -r tag port user pass; do
    [ -n "$tag" ] || continue
    found=1
    if [ -f "$STATE_FILE" ]; then
      load_state
      uri_host="$PUBLIC_HOST"
    else
      uri_host='YOUR_PUBLIC_IP_OR_DOMAIN'
    fi
    printf '\nSOCKS5（用户名密码认证）\n端口: %s\n用户名: %s\n密码: %s\n分享链接: socks5://%s:%s@%s:%s#SOCKS5-%s\n' \
      "$port" "$user" "$pass" "$(urlencode "$user")" "$(urlencode "$pass")" "$uri_host" "$port" "$port"
  done < <(jq -r '.inbounds[]? | select((.tag // "") | startswith("socks5-")) | [.tag, (.port|tostring), ((.settings.users // .settings.accounts // [])[0].user // ""), ((.settings.users // .settings.accounts // [])[0].pass // "")] | @tsv' "$CONFIG_FILE")
  if [ "$found" -eq 0 ]; then
    printf '\n当前没有 SOCKS5 入站。可运行 sb add socks5 创建。\n'
  fi
}

socks5_add() {
  need_root
  [ -f "$CONFIG_FILE" ] || die '请先运行 sb install。'
  local port username password in_use
  port="${1:-}"
  username="${2:-}"
  password="${3:-}"
  [ -n "$port" ] || port="$(ask_default 'SOCKS5 监听端口' '1080')"
  valid_port "$port" || die '端口必须是 1–65535 的整数。'
  in_use="$(jq -r --argjson p "$port" 'any(.inbounds[]?; .port == $p)' "$CONFIG_FILE")"
  [ "$in_use" = false ] || die "端口 ${port} 已被现有入站占用。"
  [ -n "$username" ] || username="$(ask_default 'SOCKS5 用户名' "sb$(openssl rand -hex 3)")"
  [[ "$username" != *:* && "$username" != *$'\n'* ]] || die '用户名不能包含冒号或换行。'
  if [ -z "$password" ]; then
    password="$(ask_password)"
  fi
  [[ "$password" != *:* && "$password" != *$'\n'* ]] || die '密码不能包含冒号或换行。'
  local next_config
  # Xray chooses the config parser from the filename suffix; keep .json last.
  next_config="$(make_temp_file .json)"
  if ! jq --argjson port "$port" --arg user "$username" --arg pass "$password" \
    '.inbounds += [{tag:("socks5-" + ($port|tostring)),listen:"0.0.0.0",port:$port,protocol:"socks",settings:{auth:"password",users:[{user:$user,pass:$pass}],udp:true}}]' \
    "$CONFIG_FILE" >"$next_config"; then
    rm -f "$next_config"
    die '无法更新 SOCKS5 配置。'
  fi
  chmod 600 "$next_config"
  apply_config_change "$next_config"
  ok "SOCKS5 已创建，监听端口 ${port}；请在 NAT 宿主机转发该 TCP 端口。"
  socks5_list
}

socks5_delete() {
  need_root
  [ -f "$CONFIG_FILE" ] || die '未找到配置。'
  local port next_config
  port="${1:-}"
  [ -n "$port" ] || die '用法：sb del socks5 <端口>'
  valid_port "$port" || die '端口必须是 1–65535 的整数。'
  jq -e --arg tag "socks5-${port}" 'any(.inbounds[]?; .tag == $tag)' "$CONFIG_FILE" >/dev/null || die "未找到端口 ${port} 的 SOCKS5 入站。"
  next_config="$(make_temp_file .json)"
  jq --arg tag "socks5-${port}" '.inbounds |= map(select(.tag != $tag))' "$CONFIG_FILE" >"$next_config"
  chmod 600 "$next_config"
  apply_config_change "$next_config"
  ok "已删除 SOCKS5 入站（端口 ${port}）。"
}

install_all() {
  need_root; need_alpine; need_openrc; ensure_dependencies
  if [ -e "$CONFIG_FILE" ] || [ -e "$INIT_FILE" ] || [ -e "$SB_BIN" ]; then
    die "检测到既有 Xray/sb 安装。为避免覆盖，请先确认来源；若是本脚本的安装，可运行：sb uninstall。"
  fi
  PORT="$(ask_default '监听端口（需在 NAT 宿主机映射 TCP）' '443')"
  valid_port "$PORT" || die '端口必须是 1–65535 的整数。'
  SNI="$(ask_default 'REALITY SNI/伪装站（自动默认）' 'www.cloudflare.com')"
  valid_hostname "$SNI" || die 'SNI 必须是合法域名，且不要包含 https:// 或端口。'
  PUBLIC_HOST="$(ask_default '分享链接中的公网 IP 或域名（NAT 环境请填宿主机公网地址）' "$(detect_public_host)")"
  [ -n "$PUBLIC_HOST" ] || die '公网地址不能为空。'
  if [ -x "$XRAY_BIN" ]; then
    "$XRAY_BIN" x25519 >/dev/null 2>&1 || die "发现已有 ${XRAY_BIN}，但它不能生成 REALITY 密钥。请确认来源并备份后再处理该文件。"
    info '复用上次安装留下的 Xray 内核…'
  else
    download_xray
  fi
  UUID="$($XRAY_BIN uuid)"
  SHORT_ID="$(openssl rand -hex 8)"
  PATH_VALUE="/xhttp-$(openssl rand -hex 8)"
  make_keys
  write_config
  write_state
  write_openrc_service
  install_manager
  rc-update add "$SERVICE" default
  rc-service "$SERVICE" start
  ok '部署完成。'
  show_info
}

restart_service() { need_root; rc-service "$SERVICE" restart; }
service_status() { rc-service "$SERVICE" status; }

update_core() {
  need_root; need_alpine; ensure_dependencies
  [ -f "$CONFIG_FILE" ] || die '未安装。'
  rc-service "$SERVICE" stop || true
  download_xray
  "$XRAY_BIN" run -test -config "$CONFIG_FILE" >/dev/null
  rc-service "$SERVICE" start
  ok 'Xray 内核已更新并通过配置测试。'
}

enable_bbr() {
  need_root
  local target='/etc/sysctl.d/99-bbr.conf'
  if ! sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    die '无法在该 LXC 中设置 BBR。通常需由宿主机允许相应 sysctl，或直接在宿主机开启。'
  fi
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >"$target"
  ok "BBR 已启用：$(sysctl -n net.ipv4.tcp_congestion_control)"
}

uninstall_all() {
  need_root
  printf '这会停止服务，并删除 Xray、配置、日志和 sb 管理命令。继续？[y/N] '
  local answer
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]] || { info '已取消。'; return; }
  rc-service "$SERVICE" stop >/dev/null 2>&1 || true
  rc-update del "$SERVICE" default >/dev/null 2>&1 || true
  rm -f "$INIT_FILE" "$XRAY_BIN" "$SB_BIN"
  rm -rf "$XRAY_DIR" /var/log/xray
  ok '已卸载。'
}

usage() {
  cat <<'EOF'
用法：
  sb install       安装并生成 VLESS + XHTTP + REALITY
  sb info          输出当前分享链接
  sb add socks5    添加带用户名密码认证的 SOCKS5 入站
  sb list socks5   列出 SOCKS5 端口、凭据和分享链接
  sb del socks5 PORT  删除指定 SOCKS5 入站
  sb socks5 add|list|del ...  SOCKS5 管理别名
  sb status        查看服务状态
  sb restart       重启服务
  sb update        更新 Xray 内核（保留配置）
  sb bbr           尝试开启 BBR（受 LXC 宿主机限制）
  sb uninstall     卸载（会二次确认）
EOF
}

main() {
  case "${1:-}" in
    install) install_all ;;
    info|url) show_info ;;
    add)
      [ "${2:-}" = socks5 ] || die '用法：sb add socks5 [端口] [用户名] [密码]'
      socks5_add "${@:3}"
      ;;
    list)
      [ "${2:-}" = socks5 ] || die '用法：sb list socks5'
      load_state
      socks5_list
      ;;
    del|delete)
      [ "${2:-}" = socks5 ] || die '用法：sb del socks5 <端口>'
      socks5_delete "${3:-}"
      ;;
    socks5)
      case "${2:-}" in
        add) socks5_add "${@:3}" ;;
        list|info) load_state; socks5_list ;;
        del|delete) socks5_delete "${3:-}" ;;
        *) die '用法：sb socks5 add|list|del ...' ;;
      esac
      ;;
    status) service_status ;;
    restart) restart_service ;;
    update) update_core ;;
    bbr) enable_bbr ;;
    uninstall|un) uninstall_all ;;
    help|-h|--help|'') usage ;;
    *) die "未知命令：$1。运行 sb help 查看帮助。" ;;
  esac
}

main "$@"
