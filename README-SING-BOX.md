# 介绍

最好用的 sing-box 一键安装脚本 & 管理脚本

# 特点

- 快速安装
- 无敌好用
- 零学习成本
- 自动化 TLS
- 简化所有流程
- 兼容 sing-box 命令
- 强大的快捷参数
- 支持所有常用协议
- 一键添加 VLESS-REALITY (默认)
- 一键添加 TUIC
- 一键添加 Trojan
- 一键添加 Hysteria2
- 一键添加 AnyTLS
- 一键添加 Shadowsocks 2022
- 一键添加 VMess-(TCP/HTTP/QUIC)
- 一键添加 VMess-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 VLESS-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 Trojan-(WS/H2/HTTPUpgrade)-TLS
- 一键启用 BBR
- 一键更改伪装网站
- 一键更改 (端口/UUID/密码/域名/路径/加密方式/SNI/等...)
- 还有更多...

## Alpine 与 NAT/LXC 扩展

此项目保留原有 sing-box 脚本功能，并额外支持 Alpine Linux 3.21 及更新版本的 OpenRC 环境（包括 Alpine 3.23 LXC）。传统协议仍由 sing-box 提供；新增的 VLESS + XHTTP + REALITY 入站由官方 Xray-core 独立服务承载，因为当前 sing-box 核心没有 XHTTP transport。原作者及许可证信息保留在项目文件中。

Alpine 基础镜像若没有 Bash，先运行 `apk add --no-cache bash`。其他支持系统可直接执行主 README 中的 `curl` 或 `wget` 一键命令；入口脚本会自动获取完整项目源码，再从本地项目目录安装管理脚本。sing-box 核心和 XHTTP 扩展使用的 Xray 核心仍分别从各自的官方发行源下载。

安装后可通过以下命令管理扩展入站：

```sh
sing-box xhttp add
sing-box xhttp list
sing-box xhttp info 443
sing-box xhttp del 443
sing-box xhttp status
sing-box xhttp update
```

运行 `sing-box` 打开交互菜单，在“添加配置”的协议列表中选择 `VLESS-XHTTP-REALITY`，也可使用快捷命令 `sing-box add xhttp`。添加时分别填写容器监听端口和 NAT 公网映射端口；若服务商一对一映射，两者填写相同值。NAT/LXC 必须由宿主机将公网 TCP 端口转发到容器监听端口；分享链接地址要填写 NAT 宿主机的公网 IP 或域名。此协议由集成的官方 Xray-core 独立服务承载（sing-box 核心目前不支持 XHTTP transport）；扩展服务在 Alpine 上由 OpenRC 管理，Xray 配置位于 `/etc/xray`。

`sing-box update sh` 从本项目发布的 GitHub Releases 获取脚本包；也可更新本地项目文件后重新运行 `bash install.sh`。

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本基于作者的自身使用需求，以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

脚本的参数非常高效率并且超级易用，请掌握参数的使用

# 文档

安装及使用：请参阅本项目的 `README-SING-BOX.md` 与 `README.md`。

# 帮助

使用：`sing-box help`

```
sing-box script v1.0 by 233boy
Usage: sing-box [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 sing-box generate reality-keypair
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
更改:
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | auto] [Public key]    更改密钥
   method [name] [method | auto]                   更改加密方式
   sni [name] [ ip | domain]                       更改 serverName
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json
   import                                          导入 sing-box/v2ray 脚本配置

管理:
   un, uninstall                                   卸载
   u, update [core | sh | caddy] [ver]             更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 sing-box 命令, 例如: sing-box bin help
   [...] [...]                                     兼容绝大多数的 sing-box 命令, 例如: sing-box generate uuid
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
反馈问题) https://github.com/jiang-chao/vless-xhttp-reality-alpine/issues
文档(doc) https://github.com/jiang-chao/vless-xhttp-reality-alpine
```
