# VLESS XHTTP REALITY for Alpine NAT/LXC

本项目在本地维护完整的 sing-box 管理脚本，并扩展支持 Alpine Linux 3.21 及更新版本（包括 Alpine 3.23 LXC/OpenRC），以及 VLESS + XHTTP + REALITY 入站。

## 内容

- `install.sh`、`sing-box.sh`、`src/`：完整的 sing-box 安装与管理脚本，保留原有协议和管理功能。
- `src/xhttp.sh`：通过主命令管理 VLESS + XHTTP + REALITY 入站，底层使用官方 Xray-core。
- `README-SING-BOX.md`：完整安装与使用说明。

## 一键安装

支持 64 位 `x86_64/amd64` 和 `aarch64/arm64`。请以 `root` 身份，在 Bash 中执行以下任一命令。入口脚本会自动下载完整项目源码后继续安装，无需手动下载、解压仓库：

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/jiang-chao/vless-xhttp-reality-alpine/main/install.sh)
```

或使用 `wget`：

```sh
bash <(wget -qO- https://raw.githubusercontent.com/jiang-chao/vless-xhttp-reality-alpine/main/install.sh)
```

需要主机可访问 GitHub，预装 Bash，以及 `curl` 或 `wget` 其中之一；安装器会按系统包管理器补齐其他依赖。Alpine 基础系统若没有 Bash，可先运行 `apk add --no-cache bash`。

## 系统支持

| 系统 | 要求 |
| --- | --- |
| Alpine Linux | 3.21 或更新版本，使用 OpenRC；包括 Alpine 3.23 LXC |
| Ubuntu / Debian | 提供 `apt-get`，并使用 systemd |
| CentOS 及兼容发行版 | 提供 `yum`，并使用 systemd；较新的兼容系统需保留 `yum` 兼容命令 |
| SUSE Linux | 提供 `zypper`，并使用 systemd |

其他 init 系统、仅有 `dnf` 而没有 `yum` 的系统，以及非上述 64 位架构尚未由安装器支持。NAT/LXC 部署还需在宿主机配置 TCP 端口转发到容器监听端口。

安装完成后，运行 `sing-box` 进入管理菜单。添加 XHTTP 入站可运行 `sing-box add xhttp`；NAT/LXC 部署还需在宿主机配置 TCP 端口转发到容器监听端口。

详细说明：

- [sing-box 完整脚本与 XHTTP 扩展](README-SING-BOX.md)

## 项目来源与许可证

sing-box 管理脚本基于 233boy 的 sing-box 脚本扩展和本地化维护；请保留原有版权与许可证声明。完整许可证见 [LICENSE](LICENSE)。
