# VLESS XHTTP REALITY for Alpine NAT/LXC

本项目在本地维护完整的 sing-box 管理脚本，并扩展支持 Alpine Linux 3.21 及更新版本（包括 Alpine 3.23 LXC/OpenRC），以及 VLESS + XHTTP + REALITY 入站。

## 内容

- `install.sh`、`sing-box.sh`、`src/`：完整的 sing-box 安装与管理脚本，保留原有协议和管理功能。
- `src/xhttp.sh`：VLESS + XHTTP + REALITY 扩展，使用官方 Xray-core 独立运行。
- `sb-xhttp-reality-alpine.sh`：独立的 Alpine/OpenRC Xray 部署脚本。
- `README-SING-BOX.md`、`README-XRAY.md`：对应安装和使用说明。

## 一键安装

支持 64 位 `x86_64/amd64` 和 `aarch64/arm64`。请以 `root` 身份在目标 Linux 主机执行；安装器会下载完整项目到临时目录，再从本地项目目录安装管理脚本：

```sh
set -e
if [ "$(id -u)" -ne 0 ]; then echo "请使用 root 运行"; exit 1; fi
need_packages=0
command -v bash >/dev/null 2>&1 || need_packages=1
command -v tar >/dev/null 2>&1 || need_packages=1
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then need_packages=1; fi
if [ "$need_packages" -eq 1 ]; then
  if [ -f /etc/alpine-release ]; then apk add --no-cache bash curl tar
  elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y bash curl tar
  elif command -v yum >/dev/null 2>&1; then yum install -y bash curl tar
  elif command -v zypper >/dev/null 2>&1; then zypper --non-interactive install bash curl tar
  else echo "未找到受支持的包管理器"; exit 1
  fi
fi
command -v bash >/dev/null 2>&1 || { echo "请先安装 bash"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "请先安装 tar"; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url="https://github.com/jiang-chao/vless-xhttp-reality-alpine/archive/refs/heads/main.tar.gz"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" -o "$tmp/project.tar.gz"
else
  wget -qO "$tmp/project.tar.gz" "$url"
fi
tar -xzf "$tmp/project.tar.gz" -C "$tmp"
cd "$tmp/vless-xhttp-reality-alpine-main"
bash install.sh
```

需要主机可访问 GitHub，并具备上表对应的包管理器；命令会在缺少 Bash、下载工具或 `tar` 时尝试安装。安装器随后会按系统包管理器补齐运行依赖。

## 系统支持

| 系统 | 要求 |
| --- | --- |
| Alpine Linux | 3.21 或更新版本，使用 OpenRC；包括 Alpine 3.23 LXC |
| Ubuntu / Debian | 提供 `apt-get`，并使用 systemd |
| CentOS 及兼容发行版 | 提供 `yum`，并使用 systemd；较新的兼容系统需保留 `yum` 兼容命令 |
| SUSE Linux | 提供 `zypper`，并使用 systemd |

其他 init 系统、仅有 `dnf` 而没有 `yum` 的系统，以及非上述 64 位架构尚未由安装器支持。NAT/LXC 部署还需在宿主机配置 TCP 端口转发到容器监听端口。

## Alpine 手动安装

Alpine 基础系统若没有 Bash，先安装 Bash：

```sh
apk add --no-cache bash
```

在完整项目目录中运行：

```sh
bash install.sh
```

安装脚本默认从本地项目文件安装管理脚本。sing-box 核心及 XHTTP 扩展使用的 Xray-core 从各自官方发行源下载。NAT/LXC 部署还需在宿主机配置 TCP 端口转发到容器监听端口。

详细说明：

- [sing-box 完整脚本与 XHTTP 扩展](README-SING-BOX.md)
- [独立 Xray Alpine 部署脚本](README-XRAY.md)

## 项目来源与许可证

sing-box 管理脚本基于 233boy 的 sing-box 脚本扩展和本地化维护；请保留原有版权与许可证声明。完整许可证见 [LICENSE](LICENSE)。
