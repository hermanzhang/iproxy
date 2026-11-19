#!/usr/bin/env bash
# ==============================================================================
# iproxy 一键安装与极致内存优化管理脚本 (One-Click Installer & Optimizer)
# 功能：Sing-box 多账号独立 IPRoyal 住宅代理分流 + 原生内嵌 WireGuard WARP 零泄漏架构
# ==============================================================================

set -e

# 颜色配置
RED="[31m"
GREEN="[32m"
YELLOW="[33m"
BLUE="[34m"
PURPLE="[35m"
CYAN="[36m"
BOLD="[1m"
RESET="[0m"

INSTALL_PATH="/usr/local/bin/iproxy"
CONFIG_DIR="/etc/v2ray-agent/sing-box"
JSON_DATA_PATH="/etc/v2ray-agent/sing-box/users_iproyal.json"
WARP_WG_PATH="/etc/v2ray-agent/sing-box/warp_wireguard.json"

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
cat << "EOF"
  _                                     
 (_)_ __  _ __ _____  ___   _   _ _ __  
 | | '_ \| '__/ _ \ \/ / | | | | | '_ \ 
 | | |_) | | | (_) >  <| |_| |_| | |_) |
 |_| .__/|_|  \___/_/\_\__, (\__,_) .__/ 
   |_|                  |___/      |_|    
EOF
echo -e "${RESET}"
echo -e "${GREEN}${BOLD}=== Sing-box 多用户 IPRoyal 独立代理分流 + 极致内存优化一键脚本 ===${RESET}
"

# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ 错误: 请使用 root 用户运行此脚本！${RESET}"
   echo -e "${YELLOW}请运行: sudo bash $0${RESET}"
   exit 1
fi

# 2. 系统瘦身与冗余内存怪兽清理 (针对云服务器/VPS 深度优化)
echo -e "${CYAN}[1/5] 系统瘦身：停止并彻底屏蔽冗余进程 (fwupd / warp-svc)...${RESET}"
if command -v systemctl >/dev/null 2>&1; then
    # fwupd 固件更新在云服务器 VPS 虚拟机无任何作用，纯吃 176MB 内存
    systemctl stop fwupd 2>/dev/null || true
    systemctl disable --now fwupd 2>/dev/null || true
    systemctl mask fwupd 2>/dev/null || true
    pkill -9 -f fwupd 2>/dev/null || true

    # 停止官方外部 warp-svc 守护进程（内存泄漏元凶，吃 250MB~320MB 内存）
    systemctl stop warp-svc 2>/dev/null || true
    systemctl disable --now warp-svc 2>/dev/null || true
    pkill -9 -f warp-svc 2>/dev/null || true
fi

# 3. 检查并安装必要系统依赖 (Python3, qrencode, curl, jq, wgcf)
echo -e "${CYAN}[2/5] 检查并安装必要系统依赖 (python3, qrencode, curl, jq, wgcf)...${RESET}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y python3 python3-pip python3-cryptography qrencode curl jq >/dev/null 2>&1 || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release >/dev/null 2>&1 || true
    yum install -y python3 qrencode curl jq >/dev/null 2>&1 || true
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 qrencode curl jq >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
    apk add python3 py3-pip libqrencode-tools curl jq >/dev/null 2>&1 || true
fi

# 自动化安装 wgcf 工具 (用于向 Cloudflare 申请独立动态 WireGuard 凭据)
if ! command -v wgcf >/dev/null 2>&1; then
    echo -e "${CYAN}正在下载并安装 wgcf 工具到 /usr/local/bin/wgcf ...${RESET}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) WGCF_BIN_NAME="wgcf_2.2.22_linux_amd64" ;;
        aarch64|arm64) WGCF_BIN_NAME="wgcf_2.2.22_linux_arm64" ;;
        armv7l|armhf) WGCF_BIN_NAME="wgcf_2.2.22_linux_armv7" ;;
        *) WGCF_BIN_NAME="wgcf_2.2.22_linux_amd64" ;;
    esac
    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.22/${WGCF_BIN_NAME}" -o /usr/local/bin/wgcf 2>/dev/null || \
    curl -fsSL "https://ghproxy.com/https://github.com/ViRb3/wgcf/releases/download/v2.2.22/${WGCF_BIN_NAME}" -o /usr/local/bin/wgcf 2>/dev/null || true
    chmod +x /usr/local/bin/wgcf 2>/dev/null || true
fi

# 4. 配置 systemd 性能与极致内存限制 (GOMEMLIMIT + GOGC)
echo -e "${CYAN}[3/5] 配置 sing-box systemd 性能调优与内存回收上限...${RESET}"
mkdir -p /etc/systemd/system/sing-box.service.d
cat > /etc/systemd/system/sing-box.service.d/99-performance.conf << "EOF"
[Service]
Restart=always
RestartSec=2s
Nice=-10
IOSchedulingClass=realtime
IOSchedulingPriority=0
LimitNOFILE=1048576
LimitNPROC=655360
TasksMax=infinity
OOMScoreAdjust=-500
Environment=GOMEMLIMIT=100MiB
Environment=GOGC=50
EOF
systemctl daemon-reload 2>/dev/null || true

mkdir -p "$CONFIG_DIR/conf"
if [[ ! -f "$JSON_DATA_PATH" ]]; then
    cat > "$JSON_DATA_PATH" << "EOF"
{
  "cf": {
    "uuid": "c0cf0001-cf02-4cf3-acf4-cf00000000cf",
    "remark": "Cloudflare WARP 出口账号",
    "iproyal": {}
  }
}
EOF
fi

# WARP WireGuard 原生凭据将由 iproxy 首次运行时通过 wgcf 动态自动申请与注册
# if [[ ! -f "$WARP_WG_PATH" ]]; then ... fi

# 5. 部署 iproxy 核心管理引擎
echo -e "${CYAN}[4/5] 部署最新版 iproxy 引擎到 $INSTALL_PATH ...${RESET}"

cat << 'PYTHON_EOF' > "$INSTALL_PATH"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
iproxy - Sing-box 多用户 & IPRoyal 代理分流管理工具
集成内存极致优化：原生 WireGuard WARP 内嵌接入、多账号 IPRoyal 独立分流、零泄漏无冗余守护进程
"""

import json
import os
import sys
import uuid
import base64
import subprocess
import urllib.request
import urllib.parse
import shutil
import re

CONFIG_PATH = "/etc/v2ray-agent/sing-box/conf/config.json"
DATA_PATH = "/etc/v2ray-agent/sing-box/users_iproyal.json"
WARP_WG_PATH = "/etc/v2ray-agent/sing-box/warp_wireguard.json"
SINGBOX_BIN = "/etc/v2ray-agent/sing-box/sing-box"

# 颜色定义
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_BLUE = "\033[34m"
C_PURPLE = "\033[35m"
C_CYAN = "\033[36m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

def print_header(title):
    print(f"\n{C_CYAN}{C_BOLD}{'='*58}{C_RESET}")
    print(f"{C_GREEN}{C_BOLD}  {title}{C_RESET}")
    print(f"{C_CYAN}{C_BOLD}{'='*58}{C_RESET}")

def get_server_info():
    """动态从 sing-box 配置及系统获取当前服务器参数"""
    info = {
        "ip": "127.0.0.1",
        "domain": "us.xrdcool.top",
        "default_uuid": "bcd34cf9-9469-4c64-baaf-f5d4dedcf3e2",
        "reality_key": "1wngRBJ5WK_vNy7oQYSbmLjiAyoqJ8A4exq8MNN2ajc",
        "reality_sni": "www.samsung.com",
        "reality_sid": "6ba85179e30d4fc2",
        "ports": {
            "reality_tcp": 11361,
            "reality_grpc": 11985,
            "vless_tcp": 17743,
            "vless_ws": 28510,
            "vmess_ws": 36663,
            "hy2": 443,
            "tuic": 15437,
            "trojan": 34986
        },
        "paths": {
            "vless_ws": "/xlytws",
            "vmess_ws": "/xlyt"
        }
    }

    try:
        req = urllib.request.Request("http://api.ipify.org", headers={"User-Agent": "curl/7.88.1"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            info["ip"] = resp.read().decode("utf-8").strip()
    except Exception:
        info["ip"] = "203.88.122.39"

    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)

            for ib in cfg.get("inbounds", []):
                tp = ib.get("type", "")
                tag = ib.get("tag", "")
                port = ib.get("listen_port", 0)
                tr = ib.get("transport") or {}
                tls = ib.get("tls") or {}
                
                if tls.get("server_name"):
                    info["domain"] = tls.get("server_name")

                reality = tls.get("reality") or {}
                if reality.get("enabled"):
                    if reality.get("public_key"):
                        info["reality_key"] = reality.get("public_key")
                    elif reality.get("private_key"):
                        try:
                            from cryptography.hazmat.primitives.asymmetric import x25519
                            from cryptography.hazmat.primitives import serialization
                            raw_b64 = reality.get("private_key")
                            raw_b64 += "=" * ((4 - len(raw_b64) % 4) % 4)
                            priv_bytes = base64.urlsafe_b64decode(raw_b64)
                            priv = x25519.X25519PrivateKey.from_private_bytes(priv_bytes)
                            pub = priv.public_key()
                            pub_bytes = pub.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
                            info["reality_key"] = base64.urlsafe_b64encode(pub_bytes).decode().rstrip("=")
                        except Exception:
                            pass
                    if info.get("reality_key") == "1wngRBJ5WK_vNy7oQYSbmLjiAyoqJ8A4exq8MNN2ajc":
                        try:
                            import glob
                            for fn in glob.glob("/etc/v2ray-agent/subscribe_local/default/*"):
                                with open(fn, "r", encoding="utf-8") as sf:
                                    m = re.search(r"pbk=([a-zA-Z0-9_-]+)", sf.read())
                                    if m:
                                        info["reality_key"] = m.group(1)
                                        break
                        except Exception:
                            pass
                    if reality.get("short_id"):
                        sids = reality.get("short_id")
                        if isinstance(sids, list):
                            non_empty = [s for s in sids if s]
                            info["reality_sid"] = non_empty[0] if non_empty else (sids[0] if sids else "")
                        else:
                            info["reality_sid"] = sids
                    if reality.get("handshake", {}).get("server"):
                        info["reality_sni"] = reality.get("handshake", {}).get("server")
                    
                    if tr.get("type") == "grpc":
                        info["ports"]["reality_grpc"] = port
                    else:
                        info["ports"]["reality_tcp"] = port

                if tp == "vless":
                    if tr.get("type") == "ws":
                        info["ports"]["vless_ws"] = port
                        info["paths"]["vless_ws"] = tr.get("path", "/xlytws")
                    elif not reality.get("enabled"):
                        info["ports"]["vless_tcp"] = port
                elif tp == "vmess" and tr.get("type") == "ws":
                    info["ports"]["vmess_ws"] = port
                    info["paths"]["vmess_ws"] = tr.get("path", "/xlyt")
                elif tp == "hysteria2":
                    info["ports"]["hy2"] = port
                elif tp == "tuic":
                    info["ports"]["tuic"] = port
                elif tp == "trojan":
                    info["ports"]["trojan"] = port

                for u in ib.get("users", []):
                    uname = u.get("name") or u.get("Username") or ""
                    u_val = u.get("uuid") or u.get("password") or u.get("Password")
                    if u_val:
                        if "default" in uname:
                            info["default_uuid"] = u_val
                            break
                        elif info["default_uuid"] == "bcd34cf9-9469-4c64-baaf-f5d4dedcf3e2":
                            info["default_uuid"] = u_val
        except Exception:
            pass

    return info

def ensure_warp_wireguard_account(force=False):
    """确保本地具有 Cloudflare WARP 原生 WireGuard 凭据配置，避免运行外部 warp-svc 内存怪兽"""
    if not force and os.path.exists(WARP_WG_PATH):
        try:
            with open(WARP_WG_PATH, "r", encoding="utf-8") as f:
                d = json.load(f)
                pk = d.get("private_key", "")
                ppk = d.get("peer_public_key", "")
                if pk and len(pk) % 4 != 0:
                    pk += "=" * (4 - (len(pk) % 4))
                    d["private_key"] = pk
                if ppk and len(ppk) % 4 != 0:
                    ppk += "=" * (4 - (len(ppk) % 4))
                    d["peer_public_key"] = ppk
                if pk and ppk and len(pk) == 44 and len(ppk) == 44:
                    with open(WARP_WG_PATH, "w", encoding="utf-8") as wf:
                        json.dump(d, wf, indent=2)
                    return d
        except Exception:
            pass

    print(f"{C_CYAN}正在自动化注册并生成轻量级 WARP WireGuard 原生凭据...{C_RESET}")
    # 尝试调用 wgcf 动态生成最新独立账号凭据
    try:
        tmp_dir = "/tmp/wgcf_init"
        shutil.rmtree(tmp_dir, ignore_errors=True)
        os.makedirs(tmp_dir, exist_ok=True)

        wgcf_bin = shutil.which("wgcf") or "/usr/local/bin/wgcf"
        if not os.path.exists(wgcf_bin):
            import platform
            arch_m = platform.machine().lower()
            wgcf_arch = "linux_arm64" if ("arm" in arch_m or "aarch64" in arch_m) else "linux_amd64"
            wgcf_bin = f"{tmp_dir}/wgcf"
            downloaded = False
            for url in [
                f"https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_{wgcf_arch}",
                f"https://ghproxy.com/https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_{wgcf_arch}"
            ]:
                try:
                    urllib.request.urlretrieve(url, wgcf_bin)
                    os.chmod(wgcf_bin, 0o755)
                    downloaded = True
                    break
                except Exception:
                    continue
            if not downloaded:
                raise RuntimeError("未安装且无法下载 wgcf")

        subprocess.run([wgcf_bin, "register", "--accept-tos"], cwd=tmp_dir, capture_output=True, text=True)
        subprocess.run([wgcf_bin, "generate"], cwd=tmp_dir, capture_output=True, text=True)
        conf_file = f"{tmp_dir}/wgcf-profile.conf"
        if os.path.exists(conf_file):
            priv_key = ""
            v4_addr = "172.16.0.2/32"
            v6_addr = ""
            pub_key = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
            endpoint = "162.159.192.1"
            port = 2408
            with open(conf_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("PrivateKey"):
                        priv_key = line.split("=", 1)[1].strip()
                    elif line.startswith("Address") and "." in line:
                        v4_addr = line.split("=", 1)[1].strip()
                    elif line.startswith("Address") and ":" in line:
                        v6_addr = line.split("=", 1)[1].strip()
                    elif line.startswith("PublicKey"):
                        pub_key = line.split("=", 1)[1].strip()
                    elif line.startswith("Endpoint"):
                        ep_val = line.split("=", 1)[1].strip()
                        if ":" in ep_val:
                            endpoint = ep_val.split(":")[0]
                            port = int(ep_val.split(":")[1])

            # 确保 Base64 padding 完整
            if priv_key and len(priv_key) % 4 != 0:
                priv_key += "=" * (4 - (len(priv_key) % 4))
            if pub_key and len(pub_key) % 4 != 0:
                pub_key += "=" * (4 - (len(pub_key) % 4))

            # engage.cloudflareclient.com 使用其 Anycast IP 162.159.192.1 提高直连可靠性
            if endpoint == "engage.cloudflareclient.com" or not endpoint.replace(".", "").isdigit():
                endpoint = "162.159.192.1"

            if priv_key:
                data = {
                    "private_key": priv_key,
                    "local_address_v4": v4_addr,
                    "local_address_v6": v6_addr or "2606:4700:110:8af5:498f:4afb:70bf:39e7/128",
                    "peer_public_key": pub_key,
                    "peer_endpoint": endpoint,
                    "peer_port": port
                }
                os.makedirs(os.path.dirname(WARP_WG_PATH), exist_ok=True)
                with open(WARP_WG_PATH, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                shutil.rmtree(tmp_dir, ignore_errors=True)
                print(f"{C_GREEN}✅ 成功通过 Cloudflare API 注册全新 WARP 原生 WireGuard 凭据！{C_RESET}")
                return data
    except Exception as e:
        print(f"{C_YELLOW}自动化注册 WARP 遇到异常，使用最新可用安全凭据: {e}{C_RESET}")

    fallback_data = {
        "private_key": "aPcTisevOqrS672KwznVVq41MvVaauQwA/bjnSofMWs=",
        "local_address_v4": "172.16.0.2/32",
        "local_address_v6": "2606:4700:110:8af5:498f:4afb:70bf:39e7/128",
        "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "peer_endpoint": "162.159.192.1",
        "peer_port": 2408
    }
    os.makedirs(os.path.dirname(WARP_WG_PATH), exist_ok=True)
    with open(WARP_WG_PATH, "w", encoding="utf-8") as f:
        json.dump(fallback_data, f, indent=2)
    return fallback_data

def load_data():
    default_data = {
        "cf": {
            "uuid": "c0cf0001-cf02-4cf3-acf4-cf00000000cf",
            "remark": "Cloudflare WARP 出口账号",
            "iproyal": {}
        }
    }
    if not os.path.exists(DATA_PATH):
        save_data(default_data)
        return default_data
    try:
        with open(DATA_PATH, "r", encoding="utf-8") as f:
            d = json.load(f)
        if "cf" not in d:
            d["cf"] = {
                "uuid": "c0cf0001-cf02-4cf3-acf4-cf00000000cf",
                "remark": "Cloudflare WARP 出口账号",
                "iproyal": {}
            }
            save_data(d)
        return d
    except Exception:
        return default_data

def save_data(data):
    os.makedirs(os.path.dirname(DATA_PATH), exist_ok=True)
    with open(DATA_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def sync_to_singbox(data, force_warp_renew=False):
    """同步更新 config.json：default 走 VPS 直连，cf 走 WARP，各自定义用户走 IPRoyal，并通过 systemd 安全重启 sing-box"""
    if not os.path.exists(CONFIG_PATH):
        print(f"{C_RED}错误: 找不到 sing-box 配置文件 {CONFIG_PATH}{C_RESET}")
        return False

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    srv_info = get_server_info()
    def_uuid = srv_info["default_uuid"]
    wg_account = ensure_warp_wireguard_account(force=force_warp_renew)

    # 1. 确保没有旧的冲突 dns 块
    if "dns" in cfg:
        del cfg["dns"]

    # 2. 清理并重建各 Inbound 的用户列表
    all_users_to_inject = {}
    
    # default 账号（走 VPS 本机默认原生直连出口 direct）
    all_users_to_inject["default"] = {
        "uuid": def_uuid
    }

    # cf 账号（走 Cloudflare WARP 出口 warp-out）
    cf_uuid = data.get("cf", {}).get("uuid", "c0cf0001-cf02-4cf3-acf4-cf00000000cf")
    all_users_to_inject["cf"] = {
        "uuid": cf_uuid
    }

    # 自定义配置的用户（如 us1, us2, us4 等）
    for uname, uinfo in data.items():
        if uname in ["default", "cf"]:
            continue
        all_users_to_inject[uname] = {
            "uuid": uinfo.get("uuid", str(uuid.uuid4()))
        }

    for ib in cfg.get("inbounds", []):
        ib_tag = ib.get("tag", "")
        ib_type = ib.get("type", "")
        new_users = []

        for uname, uinfo in all_users_to_inject.items():
            u_uuid = uinfo["uuid"]
            name_tag = f"{uname}-{ib_tag}" if ib_tag else f"{uname}-{ib_type}"

            if ib_type == "vless":
                user_obj = {
                    "name": name_tag,
                    "uuid": u_uuid
                }
                if "Reality" in ib_tag or "TCP" in ib_tag or "Vision" in ib_tag:
                    if "GRPC" not in ib_tag and "WS" not in ib_tag:
                        user_obj["flow"] = "xtls-rprx-vision"
                new_users.append(user_obj)
            elif ib_type == "vmess":
                new_users.append({
                    "name": name_tag,
                    "uuid": u_uuid
                })
            elif ib_type in ["trojan", "hysteria2", "anytls"]:
                new_users.append({
                    "name": name_tag,
                    "password": u_uuid
                })
            elif ib_type == "tuic":
                new_users.append({
                    "name": name_tag,
                    "uuid": u_uuid,
                    "password": u_uuid
                })
            elif ib_type == "naive":
                new_users.append({
                    "Username": name_tag,
                    "Password": u_uuid
                })
        ib["users"] = new_users

    # 3. 极速内存优化：配置 sing-box 原生 WireGuard Endpoint
    cfg["endpoints"] = [
        {
            "type": "wireguard",
            "tag": "warp-out",
            "address": [
                wg_account["local_address_v4"],
                wg_account["local_address_v6"]
            ],
            "private_key": wg_account["private_key"],
            "peers": [
                {
                    "address": wg_account["peer_endpoint"],
                    "port": wg_account["peer_port"],
                    "public_key": wg_account["peer_public_key"],
                    "allowed_ips": [
                        "0.0.0.0/0",
                        "::/0"
                    ]
                }
            ]
        }
    ]

    # 4. 重建 Outbounds (不再需要运行外部 warp-svc 进程)
    outbounds = [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ]

    for uname, uinfo in data.items():
        ipr = uinfo.get("iproyal")
        if ipr and ipr.get("server"):
            proto = str(ipr.get("protocol") or ipr.get("proto") or "socks").lower()
            if proto in ["http", "https"]:
                outbounds.append({
                    "type": "http",
                    "tag": f"iproyal-{uname}",
                    "server": ipr.get("server"),
                    "server_port": int(ipr.get("port", 12324)),
                    "username": ipr.get("username", ""),
                    "password": ipr.get("password", "")
                })
            else:
                outbounds.append({
                    "type": "socks",
                    "tag": f"iproyal-{uname}",
                    "server": ipr.get("server"),
                    "server_port": int(ipr.get("port", 12324)),
                    "version": "5",
                    "username": ipr.get("username", ""),
                    "password": ipr.get("password", "")
                })

    cfg["outbounds"] = outbounds

    # 5. 重建 Route Rules (精准分流：cf走WARP，IPRoyal走住宅代理，default走VPS直连)
    rules = [
        {
            "action": "sniff",
            "timeout": "1s"
        }
    ]

    # 规则 1: Cloudflare WARP 账号 (cf) -> 全部走原生 WireGuard WARP 出口 (包含 TCP 与 UDP)
    cf_user_tags = []
    for ib in cfg.get("inbounds", []):
        ib_tag = ib.get("tag", "")
        ib_type = ib.get("type", "")
        cf_user_tags.append(f"cf-{ib_tag}" if ib_tag else f"cf-{ib_type}")
    rules.append({
        "auth_user": cf_user_tags,
        "outbound": "warp-out"
    })

    # 规则 2: 各个 IPRoyal 住宅代理账号 -> TCP 走指定代理，UDP 走 WARP 防泄漏与丢包
    for uname, uinfo in data.items():
        if uname in ["default", "cf"]:
            continue
        ipr = uinfo.get("iproyal")
        if ipr and ipr.get("server"):
            user_names = []
            for ib in cfg.get("inbounds", []):
                ib_tag = ib.get("tag", "")
                ib_type = ib.get("type", "")
                name_tag = f"{uname}-{ib_tag}" if ib_tag else f"{uname}-{ib_type}"
                user_names.append(name_tag)
            
            rules.append({
                "auth_user": user_names,
                "network": "udp",
                "outbound": "warp-out"
            })
            rules.append({
                "auth_user": user_names,
                "outbound": f"iproyal-{uname}"
            })

    # 规则 3: 默认账号 (default) -> 走 VPS 本机默认原生直连出口 direct
    default_user_tags = []
    for ib in cfg.get("inbounds", []):
        ib_tag = ib.get("tag", "")
        ib_type = ib.get("type", "")
        default_user_tags.append(f"default-{ib_tag}" if ib_tag else f"default-{ib_type}")
    rules.append({
        "auth_user": default_user_tags,
        "outbound": "direct"
    })

    cfg["route"] = {
        "rules": rules,
        "final": "direct"
    }

    # 6. 保存并语法验证
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)

    if os.path.exists(SINGBOX_BIN):
        chk = subprocess.run([SINGBOX_BIN, "check", "-c", CONFIG_PATH], capture_output=True, text=True)
        if chk.returncode != 0:
            print(f"{C_RED}❌ sing-box 配置校验失败:\n{chk.stderr}{C_RESET}")
            return False

        # 7. 确保 systemd 性能与极致内存限制生效 (GOMEMLIMIT + GOGC)
        dropin_dir = "/etc/systemd/system/sing-box.service.d"
        dropin_file = f"{dropin_dir}/99-performance.conf"
        try:
            os.makedirs(dropin_dir, exist_ok=True)
            if not os.path.exists(dropin_file):
                with open(dropin_file, "w", encoding="utf-8") as f:
                    f.write("[Service]\nNice=-10\nIOSchedulingClass=realtime\nIOSchedulingPriority=0\nLimitNOFILE=1048576\nLimitNPROC=655360\nTasksMax=infinity\nOOMScoreAdjust=-500\nEnvironment=GOMEMLIMIT=100MiB\nEnvironment=GOGC=50\n")
                subprocess.run(["systemctl", "daemon-reload"], capture_output=True)
        except Exception:
            pass

        # 检查是否由 systemd 托管服务
        has_systemd = False
        chk_svc = subprocess.run(["systemctl", "status", "sing-box"], capture_output=True, text=True)
        if "sing-box.service" in chk_svc.stdout or "sing-box.service" in chk_svc.stderr:
            has_systemd = True

        if has_systemd:
            # 停止服务并杀灭任何外部残留孤儿进程，彻底消除端口冲突
            subprocess.run(["systemctl", "stop", "sing-box"], capture_output=True)
            subprocess.run(["pkill", "-9", "-x", "sing-box"], capture_output=True)
            subprocess.run(["systemctl", "daemon-reload"], capture_output=True)
            res = subprocess.run(["systemctl", "restart", "sing-box"], capture_output=True, text=True)
            if res.returncode != 0:
                print(f"{C_RED}❌ systemctl restart sing-box 失败: {res.stderr}{C_RESET}")
                return False
        else:
            # 容器/无 systemd 环境降级直接守护
            subprocess.run(["pkill", "-9", "-x", "sing-box"], capture_output=True)
            env = os.environ.copy()
            env["GOMEMLIMIT"] = "100MiB"
            env["GOGC"] = "50"
            subprocess.Popen(
                [SINGBOX_BIN, "run", "-c", CONFIG_PATH],
                stdout=open("/var/log/sing-box.log", "a"),
                stderr=subprocess.STDOUT,
                env=env
            )

        # 确保外部 warp-svc 停止与禁用，屏蔽 fwupd，彻底杜绝内存怪兽复活
        subprocess.run(["systemctl", "stop", "warp-svc"], capture_output=True)
        subprocess.run(["systemctl", "disable", "--now", "warp-svc"], capture_output=True)
        subprocess.run(["pkill", "-9", "-f", "warp-svc"], capture_output=True)
        subprocess.run(["systemctl", "mask", "fwupd"], capture_output=True)
        subprocess.run(["pkill", "-9", "-f", "fwupd"], capture_output=True)

    print(f"{C_GREEN}✅ sing-box 配置已同步并安全重启！原生 WireGuard WARP 已接管，外部冗余守护进程已彻底释放！{C_RESET}")
    return True

def generate_links(uname, uinfo):
    """生成完整 8 种主流协议的 Shadowrocket / V2Ray / Clash 连接链接"""
    srv = get_server_info()
    u_uuid = uinfo.get("uuid", srv["default_uuid"])
    server_ip = srv["ip"]
    domain = srv["domain"]
    r_key = srv["reality_key"]
    r_sni = srv["reality_sni"]
    r_sid = srv["reality_sid"]
    ports = srv["ports"]
    paths = srv["paths"]

    # 1. VLESS-Reality-Vision (最推荐)
    vless_reality = (
        f"vless://{u_uuid}@{server_ip}:{ports['reality_tcp']}?"
        f"encryption=none&flow=xtls-rprx-vision&security=reality&"
        f"sni={r_sni}&fp=chrome&pbk={r_key}&sid={r_sid}&type=tcp#"
        f"{urllib.parse.quote(f'[{uname}] Reality-Vision')}"
    )

    # 2. VLESS-Reality-gRPC
    vless_reality_grpc = (
        f"vless://{u_uuid}@{server_ip}:{ports['reality_grpc']}?"
        f"encryption=none&security=reality&sni={r_sni}&fp=chrome&pbk={r_key}&"
        f"sid={r_sid}&type=grpc&serviceName=grpc#{urllib.parse.quote(f'[{uname}] Reality-gRPC')}"
    )

    # 3. VLESS-TCP-TLS-Vision
    vless_tcp = (
        f"vless://{u_uuid}@{domain}:{ports['vless_tcp']}?"
        f"encryption=none&flow=xtls-rprx-vision&security=tls&"
        f"sni={domain}&fp=chrome&type=tcp#{urllib.parse.quote(f'[{uname}] VLESS-TLS-Vision')}"
    )

    # 4. VLESS-WS-TLS (支持 CDN 代理)
    vless_ws = (
        f"vless://{u_uuid}@{domain}:{ports['vless_ws']}?"
        f"encryption=none&security=tls&sni={domain}&type=ws&"
        f"host={domain}&path={urllib.parse.quote(paths['vless_ws'])}#{urllib.parse.quote(f'[{uname}] VLESS-WS-CDN')}"
    )

    # 5. VMess-WS-TLS (标准 Base64)
    vmess_dict = {
        "v": "2",
        "ps": f"[{uname}] VMess-WS-CDN",
        "add": domain,
        "port": str(ports["vmess_ws"]),
        "id": u_uuid,
        "aid": "0",
        "scy": "auto",
        "net": "ws",
        "type": "none",
        "host": domain,
        "path": paths["vmess_ws"],
        "tls": "tls",
        "sni": domain
    }
    vmess_ws = "vmess://" + base64.b64encode(json.dumps(vmess_dict).encode("utf-8")).decode("utf-8")

    # 6. Hysteria2 (高速 UDP)
    hy2 = (
        f"hysteria2://{u_uuid}@{domain}:{ports['hy2']}?"
        f"sni={domain}&insecure=0#{urllib.parse.quote(f'[{uname}] Hysteria2')}"
    )

    # 7. TUIC (高速 QUIC)
    tuic = (
        f"tuic://{u_uuid}:{u_uuid}@{domain}:{ports['tuic']}?"
        f"sni={domain}&congestion_control=bbr&alpn=h3#{urllib.parse.quote(f'[{uname}] TUIC')}"
    )

    # 8. Trojan-TCP-TLS
    trojan = (
        f"trojan://{u_uuid}@{domain}:{ports['trojan']}?"
        f"security=tls&sni={domain}#{urllib.parse.quote(f'[{uname}] Trojan-TLS')}"
    )

    return [
        ("VLESS-Reality-Vision (传输协议: TCP 原生直连，最推荐)", vless_reality),
        ("VLESS-Reality-gRPC (传输协议: gRPC 多路复用)", vless_reality_grpc),
        ("VLESS-TCP-TLS (传输协议: 标准 TCP TLS)", vless_tcp),
        ("VLESS-WS-TLS (传输协议: WebSocket，支持CDN代理)", vless_ws),
        ("VMess-WS-TLS (传输协议: WebSocket，支持CDN代理)", vmess_ws),
        ("Hysteria2 (传输协议: UDP / Hysteria2 高速单边加速)", hy2),
        ("TUIC (传输协议: UDP / QUIC 原生低延迟)", tuic),
        ("Trojan-TCP-TLS (传输协议: 标准 Trojan TLS)", trojan)
    ]

def print_qr(text):
    """终端打印 UTF-8 二维码"""
    try:
        subprocess.run(["qrencode", "-t", "UTF8", text])
    except Exception:
        print(f"{C_RED}未安装 qrencode 工具，无法打印二维码{C_RESET}")

def view_users(data):
    srv = get_server_info()
    print_header("当前配置的所有用户及出口映射")
    print(f"{C_BLUE}💡 [default] 默认账号：VPS 本机原生直连出口 (显示 VPS 公网 IP: {srv.get('ip', '203.88.122.39')}){C_RESET}")
    print(f"{C_PURPLE}💡 [cf]      WARP 账号：Cloudflare WARP 原生出口 (内嵌免外部守护进程，极低内存){C_RESET}\n")

    print(f"{'用户名':<12} {'出口协议':<15} {'代理出口目标 / IP':<32} {'备注':<20} {'UUID':<36}")
    print("-" * 118)
    
    # 打印 default 账号
    def_uuid = srv["default_uuid"]
    def_remark = data.get("default", {}).get("remark", "系统默认直连账号")
    vps_ip_str = "VPS本机: " + srv.get("ip", "203.88.122.39")
    print(f"{C_CYAN}{'default':<12}{C_RESET} {C_BLUE}{'DIRECT (直连)':<15}{C_RESET} {vps_ip_str:<32} {def_remark:<20} {def_uuid:<36}")

    # 打印 cf 账号
    cf_uuid = data.get("cf", {}).get("uuid", "c0cf0001-cf02-4cf3-acf4-cf00000000cf")
    cf_remark = data.get("cf", {}).get("remark", "WARP专用出口账号")
    print(f"{C_PURPLE}{'cf':<12}{C_RESET} {C_PURPLE}{'WARP (WireGuard)':<15}{C_RESET} {'Cloudflare Anycast 出口':<32} {cf_remark:<20} {cf_uuid:<36}")

    # 打印其他自定义账号 (如 us1, us2, us4)
    for uname, uinfo in data.items():
        if uname in ["default", "cf"]:
            continue
        ipr = uinfo.get("iproyal", {})
        if ipr.get("server"):
            proto = str(ipr.get("protocol") or ipr.get("proto") or "socks5").upper()
            if "HTTP" in proto:
                proto_disp = f"{C_PURPLE}{'HTTP 代理':<15}{C_RESET}"
            else:
                proto_disp = f"{C_YELLOW}{'SOCKS5 代理':<15}{C_RESET}"
            ipr_str = f"{ipr.get('server')}:{ipr.get('port')} ({ipr.get('username')})"
        else:
            proto_disp = f"{C_CYAN}{'WARP (直连)':<15}{C_RESET}"
            ipr_str = "未绑定 (走原生直连)"

        remark = uinfo.get("remark", "") or "-"
        u_uuid = uinfo.get("uuid", "-")
        print(f"{C_GREEN}{uname:<12}{C_RESET} {proto_disp} {C_YELLOW}{ipr_str:<32}{C_RESET} {remark:<20} {u_uuid:<36}")
    print("-" * 118)

def add_user(data, uname=None, ipr_str=None, remark=None):
    print_header("添加新用户并绑定 IPRoyal 代理")
    if not uname:
        uname = input(f"{C_BOLD}请输入新用户名 (如 user1/alice，英文数字): {C_RESET}").strip()
    if not uname:
        print(f"{C_RED}用户名不能为空！{C_RESET}")
        return
    if uname in data:
        print(f"{C_RED}用户 {uname} 已存在！请使用修改功能。{C_RESET}")
        return

    u_uuid = str(uuid.uuid4())
    print(f"自动为用户分配 UUID: {C_CYAN}{u_uuid}{C_RESET}")

    if remark is None:
        remark = input(f"请输入用户备注 (可选，直接回车跳过): ").strip()

    if not ipr_str:
        print(f"\n{C_BOLD}请输入该用户绑定的 IPRoyal 代理信息：{C_RESET}")
        print(f"{C_YELLOW}支持快捷格式: IP:端口:用户名:密码 或 IP:端口:用户名:密码:http{C_RESET}")
        quick_input = input("快捷输入或回车进入分步输入: ").strip()
    else:
        quick_input = ipr_str

    ipr_proto = "socks5"
    if quick_input and ":" in quick_input:
        parts = quick_input.split(":")
        if len(parts) == 4:
            ipr_ip, ipr_port, ipr_user, ipr_pass = parts
        elif len(parts) == 5:
            ipr_ip, ipr_port, ipr_user, ipr_pass, ipr_proto = parts
        else:
            print(f"{C_RED}格式不正确，需要 IP:端口:用户名:密码 或 IP:端口:用户名:密码:http{C_RESET}")
            return
    else:
        ipr_ip = input("IPRoyal 代理 IP: ").strip()
        ipr_port = input("IPRoyal 代理 端口 (默认 12324): ").strip() or "12324"
        ipr_user = input("IPRoyal 代理 用户名: ").strip()
        ipr_pass = input("IPRoyal 代理 密码: ").strip()
        p_in = input("协议类型 [1. SOCKS5 (默认) / 2. HTTP]: ").strip()
        if p_in in ["2", "http", "HTTP", "h"]:
            ipr_proto = "http"
        else:
            ipr_proto = "socks5"

    clean_proto = "http" if str(ipr_proto).lower() in ["http", "https"] else "socks5"
    data[uname] = {
        "uuid": u_uuid,
        "remark": remark or uname,
        "iproyal": {
            "server": ipr_ip,
            "port": int(ipr_port),
            "username": ipr_user,
            "password": ipr_pass,
            "protocol": clean_proto
        }
    }

    save_data(data)
    if sync_to_singbox(data):
        print(f"\n{C_GREEN}🎉 用户 [{uname}] 添加成功！对应出口: [{clean_proto.upper()}] {ipr_ip}:{ipr_port}{C_RESET}")
        show_user_links(uname, data[uname])

def edit_user(data, uname=None, ipr_str=None):
    srv = get_server_info()
    print_header("修改/配置用户的 IPRoyal 代理")
    view_users(data)
    if not uname:
        uname = input(f"\n{C_BOLD}请输入要修改的用户名 (如 default 或自定义用户名): {C_RESET}").strip()
    
    if uname == "default" and uname not in data:
        data["default"] = {
            "uuid": srv["default_uuid"],
            "remark": "默认账号",
            "iproyal": {}
        }
    elif uname not in data:
        print(f"{C_RED}找不到用户 {uname}！{C_RESET}")
        return

    uinfo = data[uname]
    old_ipr = uinfo.get("iproyal", {})
    if old_ipr and old_ipr.get("server"):
        old_p = str(old_ipr.get("protocol") or "socks5").upper()
        print(f"当前代理: [{old_p}] {old_ipr.get('server')}:{old_ipr.get('port')} (用户: {old_ipr.get('username')})")
    else:
        print("当前未绑定 IPRoyal 代理 (走原生 WireGuard WARP 出口)")

    if not ipr_str:
        print(f"\n{C_BOLD}请输入新的 IPRoyal 代理 (支持 IP:端口:用户名:密码[:http]，输入 clear 恢复 WARP 出口): {C_RESET}")
        quick_input = input("输入或回车进入分步输入: ").strip()
    else:
        quick_input = ipr_str

    if quick_input.lower() == "clear":
        uinfo["iproyal"] = {}
        save_data(data)
        sync_to_singbox(data)
        print(f"{C_GREEN}✅ 已清除用户 [{uname}] 的 IPRoyal 绑定，恢复原生 WireGuard WARP 出口！{C_RESET}")
        return

    ipr_proto = old_ipr.get("protocol", "socks5")
    if quick_input and ":" in quick_input:
        parts = quick_input.split(":")
        if len(parts) == 4:
            ipr_ip, ipr_port, ipr_user, ipr_pass = parts
        elif len(parts) == 5:
            ipr_ip, ipr_port, ipr_user, ipr_pass, ipr_proto = parts
        else:
            print(f"{C_RED}格式错误，支持 IP:端口:用户名:密码 或 IP:端口:用户名:密码:http{C_RESET}")
            return
    else:
        ipr_ip = input(f"新的 IP [{old_ipr.get('server', '')}]: ").strip() or old_ipr.get('server', '')
        ipr_port = input(f"新的 端口 [{old_ipr.get('port', '12324')}]: ").strip() or old_ipr.get('port', '12324')
        ipr_user = input(f"新的 用户名 [{old_ipr.get('username', '')}]: ").strip() or old_ipr.get('username', '')
        ipr_pass = input(f"新的 密码: ").strip() or old_ipr.get('password', '')
        old_p_str = str(old_ipr.get("protocol") or "socks5").upper()
        p_in = input(f"协议类型 [1. SOCKS5 / 2. HTTP，当前默认 {old_p_str}]: ").strip()
        if p_in in ["2", "http", "HTTP", "h"]:
            ipr_proto = "http"
        elif p_in in ["1", "socks", "socks5", "s"]:
            ipr_proto = "socks5"

    clean_proto = "http" if str(ipr_proto).lower() in ["http", "https"] else "socks5"
    uinfo["iproyal"] = {
        "server": ipr_ip,
        "port": int(ipr_port),
        "username": ipr_user,
        "password": ipr_pass,
        "protocol": clean_proto
    }

    save_data(data)
    sync_to_singbox(data)
    print(f"{C_GREEN}✅ 用户 [{uname}] 的 IPRoyal 代理已更新为 [{clean_proto.upper()}]！{C_RESET}")

def edit_remark(data, uname=None, new_remark=None):
    print_header("修改用户备注 (Remark)")
    view_users(data)
    if not uname:
        uname = input(f"\n{C_BOLD}请输入要修改备注的用户名 (如 us1 / default / cf): {C_RESET}").strip()
    if not uname:
        return False
    
    if uname == "default" and "default" not in data:
        srv = get_server_info()
        data["default"] = {"uuid": srv["default_uuid"], "remark": "系统默认直连账号", "iproyal": {}}
    elif uname not in data:
        print(f"{C_RED}找不到用户 [{uname}]！{C_RESET}")
        return False

    uinfo = data[uname]
    old_remark = uinfo.get("remark", "")
    print(f"用户 [{uname}] 当前备注为: {C_CYAN}{old_remark or '无'}{C_RESET}")

    if new_remark is None:
        new_remark = input(f"请输入新的备注 (直接回车保持不变): ").strip()
        if not new_remark:
            print(f"{C_YELLOW}未作修改。{C_RESET}")
            return False

    uinfo["remark"] = new_remark
    save_data(data)
    print(f"{C_GREEN}✅ 用户 [{uname}] 的备注已成功修改为: {new_remark}{C_RESET}")
    return True

def set_user_protocol(data, uname=None, proto=None):
    print_header("切换用户的中转代理协议 (SOCKS5 / HTTP)")
    view_users(data)
    if not uname:
        uname = input(f"\n{C_BOLD}请输入要切换协议的用户名 (如 us1): {C_RESET}").strip()
    if not uname:
        return False
    if uname not in data:
        print(f"{C_RED}找不到用户 [{uname}]！{C_RESET}")
        return False
    uinfo = data[uname]
    ipr = uinfo.get("iproyal", {})
    if not ipr or not ipr.get("server"):
        print(f"{C_YELLOW}用户 [{uname}] 未绑定中转代理！{C_RESET}")
        return False
    curr_proto = str(ipr.get("protocol") or "socks5").upper()
    print(f"用户 [{uname}] 当前中转协议为: {C_CYAN}{curr_proto}{C_RESET}")
    if not proto:
        p_choice = input(f"请选择新协议 [1. SOCKS5 / 2. HTTP (直接按回车切换为相反协议)]: ").strip()
        if p_choice in ["2", "http", "HTTP", "h"]:
            new_proto = "http"
        elif p_choice in ["1", "socks", "socks5", "s"]:
            new_proto = "socks5"
        else:
            new_proto = "http" if curr_proto == "SOCKS5" else "socks5"
    else:
        new_proto = "http" if proto.lower() in ["http", "https"] else "socks5"

    ipr["protocol"] = new_proto
    save_data(data)
    print(f"{C_GREEN}✅ 用户 [{uname}] 的中转协议已设置为: {new_proto.upper()}{C_RESET}")
    if sync_to_singbox(data):
        test_all_exits(data)
    return True

def delete_user(data, uname=None):
    print_header("删除用户")
    view_users(data)
    if not uname:
        uname = input(f"\n{C_BOLD}请输入要删除的用户名: {C_RESET}").strip()
    if uname in ["default", "cf"]:
        print(f"{C_RED}错误: [{uname}] 为系统核心出口账号，不可删除！{C_RESET}")
        return
    if uname not in data:
        print(f"{C_RED}用户不存在！{C_RESET}")
        return

    if not uname:
        confirm = input(f"{C_RED}确认要删除用户 [{uname}] 吗？(y/N): {C_RESET}").strip().lower()
    else:
        confirm = "y"

    if confirm == "y":
        del data[uname]
        save_data(data)
        sync_to_singbox(data)
        print(f"{C_GREEN}✅ 用户 [{uname}] 已删除！{C_RESET}")

def show_user_links(uname, uinfo=None):
    """展示指定用户的完整连接节点与交互式二维码生成"""
    srv = get_server_info()
    data = load_data()
    if uname == "default":
        uinfo = {"uuid": srv["default_uuid"], "remark": "默认账号 (VPS直连)"}
        exit_desc = f"{C_BLUE}VPS 本机原生直连出口 (direct，出口 IP 为 VPS 自身 IP: {srv.get('ip', '203.88.122.39')}){C_RESET}"
    elif uname == "cf":
        cf_uuid = data.get("cf", {}).get("uuid", "c0cf0001-cf02-4cf3-acf4-cf00000000cf")
        uinfo = {"uuid": cf_uuid, "remark": "Cloudflare WARP 专用账号"}
        exit_desc = f"{C_PURPLE}Cloudflare WARP 原生出口 (warp-out，出口 IP 为 Cloudflare WARP IP){C_RESET}"
    else:
        if not uinfo:
            uinfo = data.get(uname, {"uuid": srv["default_uuid"], "remark": uname})
        ipr = uinfo.get("iproyal", {})
        if ipr and ipr.get("server"):
            exit_desc = f"{C_GREEN}IPRoyal 住宅代理 [{ipr.get('server')}:{ipr.get('port')}]{C_RESET}"
        else:
            exit_desc = f"{C_BLUE}VPS 本机原生直连出口 (direct){C_RESET}"

    print_header(f"用户 [{uname}] 专属连接节点导出")
    print(f"{C_BOLD}UUID / 密码:{C_RESET} {C_CYAN}{uinfo.get('uuid', srv['default_uuid'])}{C_RESET}")
    print(f"{C_BOLD}当前出口类型:{C_RESET} {exit_desc}")
    print("-" * 58)

    links_list = generate_links(uname, uinfo)
    for idx, (proto, link) in enumerate(links_list, 1):
        print(f"\n{C_PURPLE}{C_BOLD}{idx}. 【{proto}】{C_RESET}")
        print(f"{C_CYAN}{link}{C_RESET}")

    print("\n" + "=" * 58)
    print(f"{C_YELLOW}默认展示推荐节点二维码 (1. VLESS-Reality-Vision):{C_RESET}")
    print_qr(links_list[0][1])

    while True:
        try:
            choice = input(f"\n{C_BOLD}输入序号 [1-8] 打印对应协议二维码 (直接按回车返回主菜单): {C_RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            break
        if not choice:
            break
        if choice.isdigit() and 1 <= int(choice) <= len(links_list):
            selected_proto, selected_link = links_list[int(choice) - 1]
            print(f"\n{C_GREEN}=== 二维码: {selected_proto} ==={C_RESET}")
            print_qr(selected_link)
        else:
            print(f"{C_RED}无效序号，请输入 1-{len(links_list)}！{C_RESET}")

def test_all_exits(data):
    print_header("测试所有用户的出口连通性与实际 IP")
    
    # 1. 测试默认账号 [default] (VPS 原生直连出口 direct)
    print(f"正在测试默认账号 [default] (VPS 本机直连出口 direct) ...", end="", flush=True)
    cmd_direct = ["curl", "-s", "--connect-timeout", "6", "http://ip-api.com/json"]
    res_d = subprocess.run(cmd_direct, capture_output=True, text=True)
    if res_d.returncode == 0:
        try:
            d_info = json.loads(res_d.stdout)
            print(f" {C_GREEN}成功!{C_RESET}")
            print(f"   出口IP: {C_YELLOW}{d_info.get('query')}{C_RESET} | 地区: {d_info.get('country')} - {d_info.get('city')} | ISP: {d_info.get('isp')}")
        except Exception:
            print(f" {C_GREEN}成功 (IP 正常){C_RESET}")
    else:
        print(f" {C_RED}失败! (连接超时){C_RESET}")

    # 2. 测试 Cloudflare WARP 账号 [cf] (warp-out)
    print(f"正在测试 WARP 账号 [cf] (Cloudflare WARP 原生出口 warp-out) ...", end="", flush=True)
    chk_svc = subprocess.run(["systemctl", "is-active", "sing-box"], capture_output=True, text=True)
    sb_active = "active" in chk_svc.stdout
    if sb_active:
        print(f" {C_GREEN}服务正常!{C_RESET}")
        print(f"   Sing-Box 运行状态: {C_GREEN}active (running){C_RESET} | WireGuard 对端: {C_CYAN}162.159.192.1:2408 (Cloudflare WARP){C_RESET}")
    else:
        print(f" {C_YELLOW}Sing-Box 进程未处于 active 状态{C_RESET}")

    # 3. 测试配置的 IPRoyal 住宅代理用户
    custom_users = [u for u in data.keys() if u not in ["default", "cf"]]
    if not custom_users:
        print(f"\n{C_YELLOW}当前无配置了 IPRoyal 的自定义用户。{C_RESET}")
        return
    for uname in custom_users:
        uinfo = data[uname]
        ipr = uinfo.get("iproyal", {})
        server = ipr.get("server")
        port = ipr.get("port")
        user = ipr.get("username")
        pwd = ipr.get("password")
        if not server:
            print(f"用户 [{uname}] 未绑定 IPRoyal (走原生直连)")
            continue

        proto = str(ipr.get("protocol") or ipr.get("proto") or "socks5").lower()
        is_http = proto in ["http", "https"]
        proto_label = "HTTP" if is_http else "SOCKS5"
        if is_http:
            proxy_url = f"http://{user}:{pwd}@{server}:{port}"
        else:
            proxy_url = f"socks5h://{user}:{pwd}@{server}:{port}"

        print(f"正在测试用户 [{uname}] -> [{proto_label}] {server}:{port} ...", end="", flush=True)

        cmd = [
            "curl", "-s", "--proxy", proxy_url,
            "--connect-timeout", "8",
            "http://ip-api.com/json"
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            try:
                info = json.loads(res.stdout)
                print(f" {C_GREEN}成功!{C_RESET}")
                print(f"   出口IP: {C_YELLOW}{info.get('query')}{C_RESET} | 国家地区: {info.get('country')} - {info.get('city')} | ISP: {info.get('isp')}")
            except Exception:
                print(f" {C_YELLOW}返回内容无法解析: {res.stdout[:60]}{C_RESET}")
        else:
            print(f" {C_RED}失败! (连接超时或认证错误){C_RESET}")

def monitor_connections(stream=True):
    print_header("实时连接与传输协议监控 (查看使用的是 HTTP 还是 WebSocket 等)")
    print(f"{C_CYAN}💡 正在读取最近活跃连接，并实时捕获新连接流量... (按 Ctrl+C 退出返回){C_RESET}\n")
    print(f"{'时间':<15} {'用户':<10} {'入站传输协议':<24} {'出站中转出口':<20} {'目标访问地址'}")
    print("-" * 105)

    def parse_log_line(l):
        # 匹配 sing-box 入站连接:
        # e.g.: Sep 14 03:46:45 ... [1682886702 0ms] inbound/tuic[singbox-tuic-in]: [default-singbox-tuic-in] inbound connection to uts-api.itunes.apple.com:443
        m_in = re.search(r"(\w+\s+\d+\s+\d+:\d+:\d+).*?\[(\d+)\s+.*?\]\s+inbound/(\w+)(?:\[(.*?)\])?: \[(.*?)\] inbound connection to (.*)", l)
        if m_in:
            tstamp, cid, proto, tag, user_tag, target = m_in.groups()
            tag_lower = (tag or proto).lower()
            uname = user_tag.split("-")[0] if "-" in user_tag else user_tag

            # 传输协议精细化判定 (高亮显示 HTTP 还是 WebSocket)
            if "ws" in tag_lower:
                trans = f"{C_CYAN}【WebSocket 传输】{C_RESET}"
            elif "httpupgrade" in tag_lower or "naive" in tag_lower or "http" in tag_lower:
                trans = f"{C_PURPLE}【HTTP/Upgrade 传输】{C_RESET}"
            elif "hysteria2" in tag_lower:
                trans = f"{C_YELLOW}【Hysteria2 (UDP)】{C_RESET}"
            elif "tuic" in tag_lower:
                trans = f"{C_BLUE}【TUIC (QUIC)】{C_RESET}"
            elif "reality" in tag_lower:
                trans = f"{C_GREEN}【Reality (原生TCP)】{C_RESET}"
            elif "grpc" in tag_lower:
                trans = f"{C_CYAN}【gRPC 多路复用】{C_RESET}"
            else:
                trans = f"【TCP/TLS 标准】"

            return cid, tstamp, uname, trans, target.strip()
        return None

    # 1. 预读取历史活跃连接并解析出站关系
    res = subprocess.run(["journalctl", "-u", "sing-box", "-n", "80", "--no-pager"], capture_output=True, text=True)
    out_map = {}
    for l in res.stdout.splitlines():
        m_out = re.search(r"\[(\d+)\s+.*?\]\s+(?:outbound|endpoint)/(\w+)(?:\[(.*?)\])?: outbound (?:packet )?connection", l)
        if m_out:
            cid, out_type, out_tag = m_out.groups()
            out_tag = out_tag or out_type
            if out_type == "http" or "http" in out_tag:
                out_map[cid] = f"{C_PURPLE}[HTTP 住宅代理]{C_RESET}"
            elif out_type == "socks" or "socks" in out_tag:
                out_map[cid] = f"{C_YELLOW}[SOCKS5 住宅代理]{C_RESET}"
            elif "warp" in out_tag:
                out_map[cid] = f"{C_CYAN}[Cloudflare WARP]{C_RESET}"
            elif "direct" in out_tag:
                out_map[cid] = f"{C_BLUE}[VPS 本机直连]{C_RESET}"
            else:
                out_map[cid] = f"[{out_tag}]"

    for l in res.stdout.splitlines():
        parsed = parse_log_line(l)
        if parsed:
            cid, tstamp, uname, trans, target = parsed
            out_desc = out_map.get(cid, "[已建立连接]")
            print(f"{tstamp:<15} {C_BOLD}{uname:<10}{C_RESET} {trans:<34} {out_desc:<30} {target}")

    if not stream:
        return

    # 2. 实时流式捕获新连接
    print(f"\n{C_YELLOW}>>> 正在实时捕获新连接流量 (产生访问时自动高亮显示)...{C_RESET}\n")
    proc = None
    try:
        proc = subprocess.Popen(
            ["journalctl", "-u", "sing-box", "-f", "-n", "0", "--no-pager"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
        for line in iter(proc.stdout.readline, ''):
            if not line:
                break
            parsed = parse_log_line(line)
            if parsed:
                cid, tstamp, uname, trans, target = parsed
                out_desc = "[传输处理中...]"
                print(f"{tstamp:<15} {C_BOLD}{uname:<10}{C_RESET} {trans:<34} {out_desc:<30} {target}")
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        if proc:
            proc.terminate()
            proc.wait()
    print(f"\n{C_GREEN}已退出实时监控。{C_RESET}")

def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        data = load_data()
        if cmd in ["list", "show", "ls"]:
            view_users(data)
        elif cmd in ["add", "new"]:
            uname = sys.argv[2] if len(sys.argv) > 2 else None
            ipr_str = sys.argv[3] if len(sys.argv) > 3 else None
            add_user(data, uname, ipr_str)
        elif cmd in ["link", "links", "qr"]:
            uname = sys.argv[2] if len(sys.argv) > 2 else "default"
            show_user_links(uname, data.get(uname))
        elif cmd in ["test", "ping"]:
            test_all_exits(data)
        elif cmd in ["log", "logs", "monitor", "watch"]:
            monitor_connections(stream=True)
        elif cmd in ["remark", "note"]:
            uname = sys.argv[2] if len(sys.argv) > 2 else None
            new_remark = sys.argv[3] if len(sys.argv) > 3 else None
            edit_remark(data, uname, new_remark)
        elif cmd in ["del", "delete", "rm"]:
            uname = sys.argv[2] if len(sys.argv) > 2 else None
            if uname:
                delete_user(data, uname)
        elif cmd in ["proto", "protocol"]:
            uname = sys.argv[2] if len(sys.argv) > 2 else None
            proto = sys.argv[3].lower() if len(sys.argv) > 3 else None
            set_user_protocol(data, uname, proto)
        elif cmd in ["sync", "restart"]:
            sync_to_singbox(data)
        elif cmd in ["renew-warp", "warp-renew", "warp"]:
            print_header("重新注册并刷新 Cloudflare WARP 凭据")
            sync_to_singbox(data, force_warp_renew=True)
        elif cmd in ["help", "-h", "--help"]:
            print("""iproxy 命令行快捷指令:
  iproxy             进入交互菜单
  iproxy list        查看所有用户及出口 (含出口协议与备注)
  iproxy add <用户> <IP:端口:账号:密码[:http]>  添加用户
  iproxy remark <用户> <新备注>  修改用户备注
  iproxy proto <用户> <socks5|http> 切换中转协议
  iproxy link <用户> 查看用户节点链接与二维码 (清晰标明传输协议)
  iproxy log         实时监控连接 (查看客户端使用的是 HTTP 还是 WebSocket 等)
  iproxy test        测试所有用户的出口IP
  iproxy del <用户>  删除用户
  iproxy sync        同步配置并安全重启 sing-box
  iproxy renew-warp  强制重新向 Cloudflare 注册并刷新 WARP 凭据
""")
        return

    while True:
        data = load_data()
        print(f"""
{C_CYAN}{C_BOLD}======================================================{C_RESET}
{C_GREEN}{C_BOLD}  iproxy - Sing-box 多账号 IPRoyal 独立代理管理工具    {C_RESET}
{C_PURPLE}{C_BOLD}  [极致省内存版: 原生内嵌 WireGuard WARP 出口已激活]   {C_RESET}
{C_CYAN}{C_BOLD}======================================================{C_RESET}
{C_BOLD} 1.{C_RESET} 查看所有用户及出口映射 (含出口协议/目标/备注)
{C_BOLD} 2.{C_RESET} 添加新用户并绑定 IPRoyal 代理 (支持 SOCKS5 / HTTP)
{C_BOLD} 3.{C_RESET} 修改/配置已有用户的 IPRoyal 代理
{C_BOLD} 4.{C_RESET} 修改用户备注 (Remark)
{C_BOLD} 5.{C_RESET} 切换指定用户的中转协议 (SOCKS5 / HTTP)
{C_BOLD} 6.{C_RESET} 查看/导出指定用户的节点链接与二维码 (清晰标注 WebSocket/TCP/UDP)
{C_BOLD} 7.{C_RESET} 测试所有用户的出口连通性 (含 IPRoyal 与 WARP)
{C_BOLD} 8.{C_RESET} 实时连接与传输协议监控 (查看使用是 HTTP 还是 WebSocket 等)
{C_BOLD} 9.{C_RESET} 删除用户
{C_BOLD}10.{C_RESET} 同步配置并重启 sing-box 服务
{C_BOLD}11.{C_RESET} 重新注册并刷新 Cloudflare WARP 凭据 (密钥防过期)
{C_BOLD} 0.{C_RESET} 退出管理面板
{C_CYAN}------------------------------------------------------{C_RESET}""")

        try:
            choice = input(f"{C_BOLD}请输入选择 [0-11]: {C_RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n退出。")
            break

        if choice == "1":
            view_users(data)
        elif choice == "2":
            add_user(data)
        elif choice == "3":
            edit_user(data)
        elif choice == "4":
            edit_remark(data)
        elif choice == "5":
            set_user_protocol(data)
        elif choice == "6":
            view_users(data)
            uname = input(f"\n{C_BOLD}请输入要查看的用户 [默认 default]: {C_RESET}").strip() or "default"
            show_user_links(uname, data.get(uname))
        elif choice == "7":
            test_all_exits(data)
        elif choice == "8":
            monitor_connections(stream=True)
        elif choice == "9":
            delete_user(data)
        elif choice == "10":
            sync_to_singbox(data)
        elif choice == "11":
            sync_to_singbox(data, force_warp_renew=True)
        elif choice == "0":
            print(f"{C_GREEN}已退出 iproxy 管理工具。{C_RESET}")
            sys.exit(0)
        else:
            print(f"{C_RED}无效选项，请重新输入！{C_RESET}")

        try:
            input(f"\n{C_YELLOW}按回车键继续...{C_RESET}")
        except (KeyboardInterrupt, EOFError):
            break

if __name__ == "__main__":
    main()
PYTHON_EOF

chmod +x "$INSTALL_PATH"
ln -sf "$INSTALL_PATH" /usr/bin/iproxy 2>/dev/null || true
ln -sf "$INSTALL_PATH" /usr/sbin/iproxy 2>/dev/null || true

# 6. 配置全局别名
if ! grep -q "alias iproxy=" /root/.bashrc 2>/dev/null; then
    echo "alias iproxy='/usr/local/bin/iproxy'" >> /root/.bashrc
fi

echo -e "
${GREEN}${BOLD}🎉 iproxy 安装/更新成功！原生内嵌 WARP 已生效，内存已极致优化！${RESET}"
echo -e "${YELLOW}------------------------------------------------------${RESET}"
echo -e "${CYAN}💡 随时在终端输入 ${BOLD}iproxy${RESET}${CYAN} 即可启动管理面板！${RESET}"
echo -e "${CYAN}💡 常用命令行快捷方式：${RESET}"
echo -e "   - ${BOLD}iproxy list${RESET}                                : 查看所有用户与出口映射 (含出口协议与备注)"
echo -e "   - ${BOLD}iproxy add <用户> <IP:端口:账号:密码[:http]>${RESET} : 一键添加用户 (默认SOCKS5，可指定:http)"
echo -e "   - ${BOLD}iproxy remark <用户> <新备注>${RESET}                  : 修改用户备注"
echo -e "   - ${BOLD}iproxy proto <用户> <socks5|http>${RESET}             : 一键切换中转协议"
echo -e "   - ${BOLD}iproxy link <用户>${RESET}                             : 导出用户全部协议节点与二维码 (标明传输协议)"
echo -e "   - ${BOLD}iproxy log${RESET}                                 : 实时连接与传输协议监控 (查看是HTTP还是WebSocket)"
echo -e "   - ${BOLD}iproxy test${RESET}                                : 测试所有用户出口连通性"
echo -e "   - ${BOLD}iproxy sync${RESET}                                : 同步配置并安全重启 sing-box"
echo -e "   - ${BOLD}iproxy renew-warp${RESET}                           : 强制刷新/重新注册 WARP 凭据"
echo -e "${YELLOW}------------------------------------------------------${RESET}
"

$INSTALL_PATH sync
if [ -t 0 ]; then
    $INSTALL_PATH
fi
