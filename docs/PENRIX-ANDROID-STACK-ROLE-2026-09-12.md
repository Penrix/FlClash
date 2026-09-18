# Penrix Android Stack — 职责与后续路线（2026-09-12）

## 目的

本文件冻结当前判断，避免继续把“代理分流”“域名级广告过滤”“官方 App 客户端净化”混成一个问题。

## 一、FlClash 私人版的正式职责

FlClash 继续维护，但定位收缩为 **代理与路由层**，不是 Surge 式客户端净化器。

正式职责：

1. 管理订阅、节点、代理组与 Mihomo 核心。
2. 保证 ChatGPT 在 Rule 模式下稳定使用指定住宅代理，包括 App、WebSocket 与关键域名族。
3. 提供少量明确且有现实理由的特殊路由，例如 UAA DIRECT。
4. 对需要固定走代理的私人站点提供可控、可回滚的路由增强。
5. 提供诊断能力：当前出口、命中规则、代理组、DNS、进程匹配、失败点。
6. Android / Windows 共用同一份私人路由策略，但平台诊断与系统接管逻辑分开实现。

### 不再把以下能力作为 FlClash 的核心承诺

- 不承诺通过 Mihomo 域名 REJECT 去掉 YouTube 官方 App 视频广告。
- 不承诺通过域名规则去掉 X/Twitter 官方 App Promoted 内容。
- 不承诺通过域名规则去掉 Telegram Sponsored Messages。
- MRS/domain adblock 只能作为普通广告域名/追踪域名的辅助过滤，不等于官方 App 内容净化。

## 二、当前 Android 基线

已验证 Android 私人版代码基线：

`97f45007a459527315140ed305f941a92b1abd41`

当前 `penrix-private-network` 仅在该基线上增加 Windows 本地网络审计合同。

在真实设备反馈后，下一版 Android 不应继续把“广告与追踪拦截”描述为官方 App 去广告能力。

Twitter/X 等非 P0 应用的强制路由必须以“不破坏原订阅行为”为首要约束；不能因为私人增强层而让原本无广告/稳定的使用体验回退。

## 三、官方 App 净化改用本地 Patch 路线

目标不是第三方客户端，而是：

**保留官方 App 的推荐、账号体系、UI、交互、推送、播放与产品手感，只修改广告/推广等局部客户端行为。**

策略：优先复用公开、持续维护的 patch 生态，而不是从零逆向每个 App。

### YouTube

优先评估 ReVanced / Morphe 生态的成熟 YouTube patch。

目标至少包括：

- 视频广告；
- Feed 广告/推广；
- 保留官方推荐、账号、历史、订阅、播放器体验。

### X / Twitter

优先评估 Piko（Morphe patches）。

当前已确认 Piko 提供 `Remove Ads`，目标包括 promoted posts、promoted trends、Google ads。

### Telegram

优先评估现成 Morphe / ReVanced patch bundle 中的 sponsored-message / ads removal。

Telegram patch 的来源、版本兼容与登录完整性必须单独审计，不直接套用 YouTube/X 的经验。

## 四、固定版本而不是追新

用户不要求自动追最新版。

私人构建应采用可复现冻结：

- 固定官方 App 版本；
- 固定 patch bundle 版本；
- 固定 patcher/manager/CLI 版本；
- 固定构建选项；
- 记录输入 APK/APKM SHA256；
- 记录 patch bundle SHA256；
- 记录输出 APK SHA256；
- 记录签名证书指纹；
- 建立一份已知可工作的版本清单。

只有当前固定版本出现登录、播放、推荐或服务端兼容问题时才升级。

## 五、验收标准

任何“已完成”结论必须经过真实设备验证，不能只凭 CI 或静态代码判断。

### FlClash Android

至少验证：

- Rule 模式 ChatGPT 能登录、打开历史、新对话发送、旧长对话发送、流式响应、连续发送；
- Twitter/X 不得因为私人路由层出现相对于原配置的广告/连接回退；
- 原订阅的正常分流不被私人层无理由覆盖。

### Patched App

分别验证：

- 官方账号登录/保活；
- 推荐流与历史行为正常；
- 推送正常；
- 视频/图片/下载等核心功能正常；
- 指定广告确实消失；
- 24 小时以上实际使用无明显回退。

## 六、Windows

Windows 私人版继续以 `PENRIX-WINDOWS-LOCAL-NETWORK-AUDIT-CONTRACT.md` 为入口。

优先顺序：

1. Environment Doctor / 只读诊断；
2. System Proxy 安全模式；
3. ChatGPT 路由诊断；
4. 回滚与脏状态恢复；
5. 只有环境数据证明安全后再考虑 TUN/更深系统接管。
