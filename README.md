# VLESS XHTTP REALITY for Alpine NAT/LXC

本项目在本地维护完整的 sing-box 管理脚本，并扩展支持 Alpine Linux 3.21 及更新版本（包括 Alpine 3.23 LXC/OpenRC），以及 VLESS + XHTTP + REALITY 入站。

## 内容

- `install.sh`、`sing-box.sh`、`src/`：完整的 sing-box 安装与管理脚本，保留原有协议和管理功能。
- `src/xhttp.sh`：VLESS + XHTTP + REALITY 扩展，使用官方 Xray-core 独立运行。
- `sb-xhttp-reality-alpine.sh`：独立的 Alpine/OpenRC Xray 部署脚本。
- `README-SING-BOX.md`、`README-XRAY.md`：对应安装和使用说明。

## Alpine 安装

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
