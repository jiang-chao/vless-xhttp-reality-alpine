# Alpine 3.21/3.23 LXC：VLESS + XHTTP + REALITY

一个只处理单一入站的 Alpine/OpenRC 部署脚本。它借鉴了 [233boy/sing-box](https://github.com/233boy/sing-box) 的“一键安装 + 管理命令”体验，但为 XHTTP 改用官方 Xray 内核：当前上游 `sing-box` 并不原生支持 XHTTP 传输。

## 包含内容

- VLESS + XHTTP (`mode=auto`) + REALITY；不安装其它协议
- 自动生成 UUID、REALITY 密钥、short ID 和随机 XHTTP 路径
- 默认 SNI/伪装站为 `www.cloudflare.com`，安装时可替换
- 输出 Xray/v2rayN 格式的 VLESS 分享链接
- `sb` 管理命令：`install`、`info`、`status`、`restart`、`update`、`bbr`、`uninstall`
- SOCKS5 管理：添加、列出和删除带用户名密码认证的入站
- 适配 Alpine 3.21/3.23 的 OpenRC 服务与 x86_64 / aarch64
- 下载官方 Xray 发布包时校验 SHA-256

## NAT/LXC 前提

1. LXC 必须是 Alpine 3.21 或更新版本且使用 OpenRC（能运行 `rc-service`）。
2. 宿主机/上游 NAT 必须把一个 **TCP** 端口转发到 LXC 的同一个端口；默认使用 443。
3. 安装时的“公网 IP 或域名”仅用于生成分享链接。NAT 环境务必填写 NAT 宿主机的公网地址，而不是 LXC 内网地址。
4. BBR 是否可在容器内开启由宿主机的 sysctl 权限决定；失败时请在宿主机开启。

## 安装

将 `sb-xhttp-reality-alpine.sh` 上传到 LXC 后执行：

```sh
apk add --no-cache bash
bash sb-xhttp-reality-alpine.sh install
```

安装完成后，管理命令为：

```sh
sb info
sb add socks5
sb list socks5
sb del socks5 1080
sb status
sb restart
sb update
sb bbr
```

`sb add socks5` 会交互询问端口和用户名，并自动生成强随机密码。也可以非交互添加：

```sh
sb add socks5 1080 myuser '替换成自己的强密码'
```

每个 SOCKS5 入站默认启用密码认证。请在 NAT 宿主机将该 TCP 端口转发到 LXC；如果需要 SOCKS5 UDP 功能，也要转发相同的 UDP 端口。`sb info` 和 `sb list socks5` 会显示连接信息及分享链接。删除示例：`sb del socks5 1080`。

配置文件：`/etc/xray/config.json`；管理命令：`/usr/local/bin/sb`；服务名：`xray-vless`。

## 许可证与说明

本实现采用 GPL-3.0-or-later。请在发布到自己的 GitHub 时保留 SPDX 头和本说明中的来源归属。请仅在符合当地法律、网络服务商和平台规则的前提下使用。
