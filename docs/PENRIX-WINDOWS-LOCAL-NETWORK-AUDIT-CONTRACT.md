# Penrix Windows 本地网络环境只读采集合同

用途：为 `Penrix/FlClash` 的 Windows 私人版建立真实本机网络基线，避免在复杂 Windows 环境中盲目启用 System Proxy / TUN / DNS 接管。

> **这是只读审计任务。不要修改系统配置。不要启停服务。不要安装/卸载驱动。不要改注册表、路由、DNS、代理、防火墙、网卡、WSL、Hyper-V、Docker 或 FlClash 设置。**

## 0. 输出与隐私边界

### 输出文件

请在仓库外的本地临时目录生成：

- `PENRIX-WINDOWS-NETWORK-AUDIT.md`：人类可读报告。
- `PENRIX-WINDOWS-NETWORK-AUDIT.json`：结构化原始摘要，便于后续程序解析。

**不要把采集结果 commit / push 到 GitHub。** 当前仓库是公开仓库。完成后由用户把这两个文件直接上传给 ChatGPT。

### 必须脱敏 / 禁止采集

不要输出或保存：

- 任何代理订阅 URL、token、密码、API key、cookie、Authorization header；
- Wi-Fi 密码；
- 浏览器历史、书签、下载记录；
- ChatGPT / Google / GitHub / Telegram 等账号内容；
- Clash/Mihomo 节点服务器地址、端口、UUID、密码、私钥；
- SSH/GPG/证书私钥；
- 浏览内容或正在访问的网站列表。

允许保留用于网络拓扑判断的信息：

- 网卡名称、接口类型、接口 metric；
- 私网 IPv4/IPv6 地址与网关；
- DNS 服务器地址；
- 本机监听端口及其 owning process；
- 已安装/正在运行的网络相关软件、服务、驱动名称；
- 系统代理状态；
- 路由表；
- Windows build / 架构；
- FlClash/Mihomo 本地配置路径和文件名（但不得输出其中的 secret 内容）。

机器名和 Windows 用户名可以统一替换成 `<REDACTED-HOST>` / `<REDACTED-USER>`。

---

# 1. 系统基线

采集：

- Windows Edition / Version / Build；
- x64 / ARM64；
- 当前 PowerShell 版本；
- 当前进程是否 elevated/admin；
- 系统时区；
- Fast Startup 状态（如可安全读取）；
- 当前网络类别（Public / Private / Domain）。

推荐只读命令：

```powershell
Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsBuildNumber,OsArchitecture,TimeZone
$PSVersionTable
Get-NetConnectionProfile
```

---

# 2. 网卡、虚拟网卡与绑定

采集全部网卡，不只物理网卡：

- Name / InterfaceDescription；
- ifIndex；
- Status；
- LinkSpeed；
- MacAddress（可只保留前 3 组 OUI 或直接脱敏）；
- InterfaceMetric；
- DHCP；
- IPv4 / IPv6 binding 状态；
- 明确标记疑似：Wintun / TAP / WireGuard / Clash / Mihomo / Hyper-V / WSL / Docker / VMware / VirtualBox / Tailscale / ZeroTier 等虚拟接口。

推荐：

```powershell
Get-NetAdapter -IncludeHidden
Get-NetIPInterface -AddressFamily IPv4
Get-NetIPInterface -AddressFamily IPv6
Get-NetAdapterBinding
Get-NetIPConfiguration -All
```

---

# 3. 地址、默认路由与路由竞争

必须同时采 IPv4 / IPv6：

- 每个接口的地址；
- 默认网关；
- 所有 `0.0.0.0/0` 和 `::/0` 默认路由；
- route metric + interface metric；
- 是否存在多个默认路由竞争；
- 是否存在指向 Wintun/TAP/Hyper-V/WSL/Docker 等接口的特殊路由；
- 本地回环与 RFC1918 / CGNAT 网段路由。

推荐：

```powershell
Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix,RouteMetric
Get-NetRoute -AddressFamily IPv6 | Sort-Object DestinationPrefix,RouteMetric
route print
```

报告里额外给出一段结论：

- `当前 IPv4 默认出口接口 = ?`
- `当前 IPv6 默认出口接口 = ?`
- `是否存在路由竞争 = yes/no`

---

# 4. DNS / DoH / NRPT / hosts

采集：

- 每个接口 DNS Server；
- DHCP DNS vs 手动 DNS；
- DNS suffix / search list；
- Windows DoH 相关可读状态；
- NRPT policy；
- `hosts` 是否存在非注释条目（只报告 hostname 和目标 IP；若明显涉及私密内网命名，可脱敏 hostname）；
- 是否存在 127.0.0.1 / ::1 本地 DNS stub；
- 当前是否有程序监听 TCP/UDP 53、853、5353、5355。

推荐：

```powershell
Get-DnsClientServerAddress
Get-DnsClient
Get-DnsClientGlobalSetting
Get-DnsClientNrptPolicy
Get-Content "$env:SystemRoot\System32\drivers\etc\hosts"
```

如读取 DoH 注册表，只读即可，不得写入。

---

# 5. Windows 代理状态

必须区分：

## WinINET / System Proxy

读取：

- ProxyEnable；
- ProxyServer；
- ProxyOverride；
- AutoConfigURL / PAC；
- AutoDetect。

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
```

## WinHTTP

```cmd
netsh winhttp show proxy
```

## 环境变量代理

只报告变量是否存在和 host:port；若值里包含账号密码/token则脱敏：

- HTTP_PROXY
- HTTPS_PROXY
- ALL_PROXY
- NO_PROXY
- lowercase variants

## 应用级代理

只检查网络工具相关应用是否有独立代理配置入口/进程，不读取账号数据。

---

# 6. 本机监听端口与潜在冲突

只采集 **LISTENING / UDP local endpoint**，不要导出当前远程连接和浏览目标。

重点标记：

- 53 / 80 / 443；
- 7890 / 7891 / 7892；
- 9090 / 9091；
- 1080 / 10808 / 10809；
- 5353 / 5355；
- 8118 / 8888；
- 任何由 clash / mihomo / flclash / v2ray / xray / sing-box / tailscale / zerotier / wireguard / openvpn 等进程占用的端口。

推荐：

```powershell
Get-NetTCPConnection -State Listen | Sort-Object LocalPort
Get-NetUDPEndpoint | Sort-Object LocalPort
Get-Process
```

输出 `local address : local port -> process name / PID`。

---

# 7. 网络相关进程 / 服务 / 驱动

只筛网络相关，不要列整个软件资产清单。

重点关键词：

- FlClash / Clash / Mihomo；
- v2ray / xray / sing-box；
- WireGuard / OpenVPN；
- Tailscale / ZeroTier；
- Cloudflare WARP；
- AdGuard；
- Docker；
- VMware / VirtualBox；
- Hyper-V / HNS / vmcompute；
- WSL；
- 第三方防火墙 / 网络过滤 / 安全软件；
- 抓包工具（Wireshark/Npcap/Fiddler/Charles/Proxifier 等）。

采集：

- process name / executable path；
- service name / state / start type；
- 相关网络驱动名称与状态（若可只读获得）。

不得停止这些进程或服务。

---

# 8. WSL / Hyper-V / Docker / 虚拟化

采集是否启用以及网络模式线索：

```cmd
wsl --status
wsl -l -v
```

只读检查：

- WSL1 / WSL2；
- `.wslconfig` 是否存在，若存在只读取 networkingMode、dnsTunneling、firewall、autoProxy、localhostForwarding 等网络字段；其他内容不必输出；
- Hyper-V；
- Virtual Machine Platform；
- Windows Hypervisor Platform；
- Docker Desktop / HNS；
- VMware / VirtualBox。

不要修改这些组件。

---

# 9. Loopback / UWP / AppContainer

FlClash Windows 当前仓库包含 `EnableLoopback.exe`，因此需要确认本机现状。

采集：

```cmd
CheckNetIsolation LoopbackExempt -s
```

并报告：

- 当前是否已有 loopback exemptions；
- 是否存在与 ChatGPT / Microsoft Store / UWP 网络相关的 AppContainer 条目；
- 不要新增或删除 exemption。

---

# 10. Windows Firewall / 安全过滤

只读：

- 当前三个 Firewall Profile 状态；
- 与 FlClash / Mihomo / Clash / WireGuard / Wintun / OpenVPN / Tailscale / ZeroTier 等相关的显式规则；
- 是否存在第三方防火墙或网络过滤驱动；
- Windows Defender Network Protection 状态（如容易读取）。

不要导出全部几千条防火墙规则；只筛相关条目。

---

# 11. FlClash / Mihomo 当前本机状态

如果本机已经装过 FlClash / Clash / Mihomo：

采集：

- 安装路径；
- 数据目录；
- 版本；
- 当前是否运行；
- 当前运行模式：Rule / Global / Direct（如果能从本地状态安全确定）；
- System Proxy 开关；
- TUN 开关；
- mixed/http/socks/controller/dns 本地监听端口；
- `find-process-mode`；
- TUN stack / auto-route / auto-detect-interface / strict-route 等网络相关字段；
- DNS mode（fake-ip / redir-host 等）；
- IPv6 开关。

**不得输出：**

- subscription URL；
- proxy 节点 server / port / uuid / password / key；
- provider URL 中带 token 的部分。

如果需要读取 YAML，请只抽取上述安全字段并脱敏其余内容。

---

# 12. ChatGPT 专项本地条件

只检查网络条件，不访问用户聊天内容。

采集：

- `ChatGPT.exe` 是否安装 / 正在运行；
- 可执行文件路径和版本；
- Chrome / Edge 是否为主要浏览器（只报告存在与版本，不采历史）；
- `chatgpt.com`、`openai.com`、`ws.chatgpt.com` DNS 是否能解析；
- TCP 443 是否可建立；
- 如能安全测试 WebSocket handshake，可做最小握手测试，但不要携带 ChatGPT 登录 cookie/token；
- 不要自动登录 ChatGPT；
- 不要读取聊天数据。

输出一段结论：

- Desktop ChatGPT 是否适合使用 `PROCESS-NAME`；
- Browser ChatGPT 是否必须靠 DOMAIN/WebSocket 路由；
- 是否发现本地 DNS / proxy / firewall / route 冲突风险。

---

# 13. IPv6 专项

单独总结：

- 系统是否启用 IPv6；
- 默认 IPv6 路由是否存在；
- DNS 是否返回 AAAA；
- 当前代理/TUN 是否明显只接管 IPv4；
- 是否存在潜在 IPv6 leak / bypass 风险。

不要为了测试而禁用 IPv6。

---

# 14. 最终报告必须包含的结论

`PENRIX-WINDOWS-NETWORK-AUDIT.md` 最前面先给摘要：

## A. 当前网络控制权

明确判断：

- 谁在控制 System Proxy；
- 谁在控制 TUN / 默认路由；
- 谁在控制 DNS；
- 是否存在多个代理/VPN同时工作的迹象。

## B. 冲突风险清单

按严重度：

- P0：会导致 FlClash 私人版直接断网/错误路由；
- P1：可能影响 ChatGPT 稳定、DNS、WebSocket；
- P2：兼容性/性能/维护风险。

## C. 建议接管模式

只给建议，不执行：

- `System Proxy only` 是否安全；
- `TUN` 是否安全；
- 是否需要先保留/排除某些虚拟网卡；
- DNS 应该由谁管理；
- IPv6 是否需要特殊处理；
- WSL/Docker 是否需要特殊路由。

## D. 需要 ChatGPT 后续决定的问题

列出仍然不能仅靠本机事实自动决定的事项。

---

# 15. JSON 最低结构

`PENRIX-WINDOWS-NETWORK-AUDIT.json` 至少包含：

```json
{
  "os": {},
  "network_profiles": [],
  "adapters": [],
  "ip_interfaces": [],
  "routes_v4": [],
  "routes_v6": [],
  "dns": {},
  "proxy": {
    "wininet": {},
    "winhttp": {},
    "environment": {}
  },
  "listeners": [],
  "network_processes": [],
  "network_services": [],
  "virtualization": {},
  "loopback_exemptions": [],
  "firewall": {},
  "flclash_mihomo": {},
  "chatgpt": {},
  "ipv6": {},
  "risks": [],
  "collection_errors": []
}
```

命令失败时不要为了“拿全数据”修改系统；把错误写进 `collection_errors` 即可。

---

# 16. 执行原则

1. Read-only first。
2. 不猜；无法确定就记录 `unknown`。
3. 不为了测试而改网络。
4. 不自动关闭任何 VPN / Proxy / Firewall。
5. 不 commit 采集结果。
6. 不泄漏 secret。
7. 报告事实和风险，不提前替用户决定最终 TUN/DNS 架构。
8. 完成后告诉用户两个本地输出文件的绝对路径，由用户直接上传给 ChatGPT。
