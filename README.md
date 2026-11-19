# iproxy

**Sing-box 多用户独立 IPRoyal 住宅代理分流 + 原生内嵌 WireGuard WARP 极致内存优化管理系统**

---

## 🌟 核心特性

- 🎯 **多用户独立代理分流**：支持添加多个独立用户，并为每个用户绑定各自的 IPRoyal 住宅代理（支持 SOCKS5 / HTTP 协议）。TCP 流量直达住宅代理，UDP 流量由 WARP 接管防 DNS 泄漏与丢包。
- 🛡️ **原生 WireGuard WARP 内嵌**：无需在 VPS 上常驻官方臃肿的 `warp-svc` 守护进程（彻底杜绝 250MB~320MB 内存泄漏），通过 `wgcf` 自动生成 Cloudflare WARP 凭据并由 Sing-box 原生 WireGuard Endpoint 直接承载。
- 🚀 **极致内存与系统调优**：
  - 深度屏蔽 VPS 虚拟机无用后台进程（如 `fwupd` 固件更新、外部 `warp-svc`）。
  - 配置 Sing-box systemd 环境变量限制：`GOMEMLIMIT=100MiB` 与 `GOGC=50`。
  - 核心服务内存占用控制在 **10MB ~ 20MB** 级别。
- 🌐 **全主流入站协议自动适配**：
  - **VLESS-Reality-Vision**（原生 TCP 直连，首选推荐）
  - **VLESS-Reality-gRPC**（gRPC 多路复用）
  - **VLESS-TCP-TLS-Vision**
  - **VLESS-WS-TLS**（支持 CDN 代理）
  - **VMess-WS-TLS**（标准 Base64 订阅链接）
  - **Hysteria 2**（UDP / QUIC 高速单边加速）
  - **TUIC**（UDP / QUIC 低延迟）
  - **Trojan-TCP-TLS**
- 📱 **终端二维码与节点导出**：终端内置 UTF-8 字符二维码生成，支持 Shadowrocket、Clash Verge Rev、Sing-box、NekoBox、v2rayN 一键扫码或复制导入。
- 📊 **实时连接与传输协议监控**：实时解析活跃流量，清晰判断客户端使用的是 WebSocket 还是 HTTP/Upgrade，并展示目标去向（Direct / WARP / IPRoyal）。

---

## 🚀 一键安装

在已配置好基础环境的 VPS 上执行以下一键命令：

```bash
curl -fsSL https://raw.githubusercontent.com/hermanzhang/iproxy/main/install.sh | bash
```

安装完成后，全局自动注册 `iproxy` 命令，随时在终端输入 `iproxy` 即可呼出管理面板。

---

## 📋 命令行快捷用法

除了进入交互式菜单，`iproxy` 还支持丰富的直接 CLI 命令行参数：

| 命令 | 说明 |
| :--- | :--- |
| `iproxy` | 进入交互式多功能管理面板 |
| `iproxy list` | 查看所有用户及当前出口映射（Direct / WARP / IPRoyal） |
| `iproxy add <用户> <IP:端口:账号:密码[:http]>` | 一键添加新用户并绑定代理（默认 SOCKS5，加 `:http` 为 HTTP） |
| `iproxy remark <用户> <新备注>` | 修改用户备注 |
| `iproxy proto <用户> <socks5\|http>` | 一键切换指定用户的代理中转协议 |
| `iproxy link <用户>` | 导出指定用户的全部 8 种协议链接与二维码（默认展示 `default`） |
| `iproxy test` | 批量测试所有用户的出口连通性及公网出口 IP |
| `iproxy log` | 实时流式监控连接流量（查看传输协议与出站映射） |
| `iproxy sync` | 同步配置并安全重启 Sing-box 服务 |
| `iproxy renew-warp` | 强制重新向 Cloudflare 申请并刷新 WARP WireGuard 凭据 |

---

## 💡 前置说明与使用流程

本脚本定位为 **Sing-box 增强型分流与内存优化引擎**，依赖于已部署好 Sing-box 基础环境（如 [v2ray-agent](https://github.com/mack-a/v2ray-agent) 八合一脚本）。

### 新 VPS 推荐两步部署法：

1. **第一步：安装 Sing-box 核心并绑定域名**
   ```bash
   wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
   ```
   *选择安装 Sing-box 核心，并完成域名证书配置。*

2. **第二步：运行 iproxy 一键增强与优化**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/hermanzhang/iproxy/main/install.sh | bash
   ```
   *脚本将自动读取现有配置，无缝接入原生 WARP、IPRoyal 代理分流及内存上限调优。*

---

## 📄 License

MIT License.
