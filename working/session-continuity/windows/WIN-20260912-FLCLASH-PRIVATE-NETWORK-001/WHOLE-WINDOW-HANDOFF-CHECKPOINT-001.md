# Whole-Window Handoff Checkpoint 001 — FlClash / Penrix Private Network

- `window_id`: `WIN-20260912-FLCLASH-PRIVATE-NETWORK-001`
- `transfer_id`: `HANDOFF-WIN-20260912-FLCLASH-PRIVATE-NETWORK-001-001`
- `source_window`: 当前已到上下文上限的 FlClash / Penrix Private Network 开发窗口
- `target_window`: 下一新 ChatGPT 窗口
- `transfer_type`: `whole-window blind transfer`
- `scope`: `full`
- `repository`: `Penrix/FlClash`
- `working_branch`: `penrix-private-network`
- `source_repo_commit_at_capture`: `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`
- `source_tree_at_capture`: `6e9f96fe08902b8fa8a14b6394c6b90638915c05`
- `draft_pr`: `#1` — `Penrix private network – Android reliability experiments`
- `capture_date`: `2026-09-13`（用户本地时间）

> 这是 Whole-Window Blind Transfer，不是 Fresh Onboarding，也不是项目简介。
>
> 新窗口的目标不是重新讨论“想做什么”，而是恢复本窗口已经形成的产品坐标、技术裁决、验证事实、被排除方向、代码状态与下一步工作位置，然后继续。

---

## 0. 恢复总原则

1. **仓库 live state 优先于本文件里的历史 SHA。** 本文件记录的是交接时的语义现场；恢复时必须先确认 `penrix-private-network` 当前 HEAD 和最新 CI 是否又向前推进。
2. 本文件负责恢复“为什么这么做、什么已经裁决、什么不能退回、现在卡在哪里”。代码本身负责回答最终实现细节。
3. 不要要求用户重新解释本窗口历史；本 handoff 应被视为足够完成盲续接的主语义载荷。
4. 不把“曾经尝试过”写成“当前仍采用”；尤其注意后台强拉活 / task-removal 方向已经被后续裁决淘汰。
5. 严格区分：
   - 已实现并进入仓库；
   - CI 已验证；
   - 真机已验证；
   - 仅为后续候选。
6. 当前 Android 可靠性工作的母问题不是“让 App 怎么都死不了”，而是：
   **Penrix 开着时，真实网络数据面应持续可用；一旦失效，要先识别坏在哪一层，再做有界、最小化恢复。**

---

# 1. 产品坐标与架构边界

## 1.1 FlClash / Mihomo 在私人体系中的角色

本 fork 不是为了把 FlClash 改造成万能内容过滤器。

它是 **网络层**：

- 代理节点与隧道；
- 路由策略；
- DNS；
- ChatGPT 特殊路由；
- UAA Direct；
- 私人站点路由；
- 网络诊断；
- Android 后台 / VPN 可靠性；
- Windows 对应的系统网络层能力。

内容/UI 层由“基于官方代码/官方 APK 体系的本地补丁 App”处理，例如：

- X / Twitter → Piko NewX + Morphe 路线；
- YouTube → Morphe 为主，吸收 Anddea/RVX 的好思路；
- Telegram → 待审计的 Morphe patch 路线。

**硬边界：不要因为 X / YouTube 的第一方广告需要 App patch，就把 FlClash 的网络增强删掉。两层是互补，不是替代。**

## 1.2 Android 前提

- 无 root。
- 不依赖系统级通用 HTTPS MITM 去处理所有原生 App 第一方内容。
- Android 7+ 用户 CA 信任和证书固定意味着“无 root + 未改官方 App”不能假定可做 Surge 式通用内容改写。
- 对用户来说签名不是关键；稳定、可长期使用的私人版本比追新版本更重要。

## 1.3 用户使用环境中与技术裁决相关的事实

- 主力是 Windows + Android。
- Android 无 root。
- 当前代理底层是较稳定的美国住宅网络；此前观察到 ASN `AS22773 / Cox Communications`。
- 用户更关注稳定性、原生体验、长期可用，而不是频繁升级和“功能越多越好”。
- 既有浏览器广告可由 uBlock 等处理；本 fork 的重点不是复制浏览器广告插件。

---

# 2. 当前 branch 与提交现场

交接捕获时：

- branch: `penrix-private-network`
- HEAD: `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`
- HEAD message: `chore(android): register private package ids`

从关键 Android 数据面恢复 commit `72ccedc589cd3b977e1db6c13a2088ccda8c8a52` 到交接 HEAD，branch 正好领先 5 个 commit：

1. `3b7ed323e4335a074f1018f345f5d08df772486a` — `chore(private): restore FlClash app name`
2. `ed7afb83a7461930816df6871a5cc6611e6bb048` — `chore(private): restore FlClash Android labels`
3. `cca32d9e6060711483a5f8dd69195db9cfe59bc9` — `fix(private): keep upstream hotkey equality`
4. `7aa78e32b3edbc6c27b3c034ab3ec67beaf773c8` — `chore(android): isolate private FlClash package`
5. `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a` — `chore(android): register private package ids`

这 5 个 commit 修改范围集中在：

- `android/app/build.gradle.kts`
- `android/app/google-services.json`
- `android/common/src/main/res/values/strings.xml`
- `lib/common/constant.dart`

语义：在数据面恢复工作之后，继续收拢私人 Android 包身份 / App 名称 / label，同时修正了一个不应被私人改动破坏的 upstream hotkey equality 行为。

---

# 3. 已完成：Android DEBUG 角标修复

## 3.1 根因

不是 Flutter 默认的 `debugShowCheckedModeBanner`；主 `Application` 原本已经关闭默认 debug banner。

真正来源在：

`lib/manager/app_manager.dart`

`AppEnvManager` 自己对 pre/debug 环境包了一层：

```dart
if (kDebugMode) {
  if (globalState.isPre) {
    return Banner(
      message: 'DEBUG',
      location: BannerLocation.topEnd,
      child: child,
    );
  }
}
```

## 3.2 实现

commit:

`109a4afe522d989fe167ab1cc686fba525dc58cd` — `fix(android): hide environment debug banner`

Android 私人包在进入上述环境 banner 逻辑前直接返回 child：

```dart
if (system.isAndroid) {
  return child;
}
```

因此：

- Android 私人 APK 不再显示丑陋的 `DEBUG` ribbon；
- debug logging / debuggability 不需要为此被拿掉；
- desktop/pre 原语义不被一刀切破坏。

---

# 4. 已完成：DNS `0.0.0.0:7874 address already in use`

## 4.1 根因

用户真机出现：

`Start DNS server(UDP) error: listen udp 0.0.0.0:7874: bind: address already in use`

事实链：

- `7874` 不是 Penrix fork 硬编码出来的；
- 用户来源配置 / 订阅中携带 `dns.listen: 0.0.0.0:7874`；
- upstream profile builder 会保留自己无法编辑的 raw DNS key，包括 `listen`；
- Mihomo 因此尝试启动一个对外 UDP DNS listener；
- Android TUN/VPN 模式已经有自己的 DNS hijack 路径，该外部 listener 在私人 Android VPN 场景不是必须的，并可能与旧实例或其他进程抢端口。

## 4.2 实现链

相关 commits：

- `3d322837ad2a27682199059522030db948390b35` — `test(android): cover DNS listener sanitizing`
- `160eb34f55a78f6f0d9ea5ea32e5ab43fc8bd4fd` — `fix(android): suppress external DNS listener in private VPN`
- `c8f12cc6907800b4513daed88ddd10006357ddc3` — `fix(android): add DNS listener sanitizer`
- `7f4b156ca1e39ba7e2b37386a19a2939bd0d4f93` — `fix(android): scope DNS listener suppression to VPN mode`

核心 helper：

`lib/common/penrix_android_dns.dart`

核心函数：

`stripExternalDnsListenFromYaml(String source)`

它只删除顶层 `dns:` 下的直接 child `listen:`，保留：

- `enable`
- `enhanced-mode`
- `nameserver`
- `fake-ip`
- `nameserver-policy`
- `fallback`
- nested structures
- nested `listen`

私人 wrapper 位于：

`lib/providers/action.dart`

逻辑发生在 upstream 已经生成最终 normalized YAML **之后**：

```dart
if (!Platform.isAndroid || !data.realPatchConfig.tun.enable) {
  return result;
}

final sanitizedYaml = stripExternalDnsListenFromYaml(result.yaml);
if (sanitizedYaml == result.yaml) {
  return result;
}
return (yaml: sanitizedYaml, md5: sanitizedYaml.toMd5());
```

## 4.3 边界

- 只在 `Android && TUN enabled` 时抑制外部 DNS listener。
- pure proxy 模式保留原本 `dns.listen` 能力。
- 修改 YAML 后重新计算 MD5。
- 不要退回“把 7874 改成 7875”这种治标方案。

回归测试：

`test/common/penrix_android_dns_test.dart`

覆盖：

- 直接 `dns.listen` 被移除；
- 其他 DNS 字段保留；
- nested `listen` 不被误删；
- 没有目标字段时文本保持不变。

---

# 5. Android 后台 / VPN 可靠性：历史尝试与当前裁决

这里最容易在新窗口发生方向回退，必须严格区分。

## 5.1 仍保留的 sticky foreground VPN 基础

commit:

`05e30c8a55c719662e08fe646e4e7317626a99a9` — `fix(android): keep VPN service sticky after successful start`

文件：

`android/service/src/main/java/com/follow/clash/service/VpnService.kt`

私人 action：

`com.follow.clash.service.intent.action.PENRIX_KEEP_ALIVE`

核心语义：

- 正常/system/Always-on 启动仍通知 App 状态机；
- `onStartCommand()` 返回 `START_STICKY`；
- 成功启动 modules/profile 后，使用内部 keep-alive action 把 VPN 变成显式 started foreground service；
- 内部 keep-alive action 不递归重启 profile；
- 显式 stop 会正常清理 modules/TUN 并 `stopSelf()`。

这属于合理的 Android VPN 生命周期基础，**不是 alarm-loop 强拉活**。

## 5.2 被淘汰方向：recent-task swipe / task removal 强复活

历史上曾出现：

- `ef2c88fe33c179b1e921448dd518cd4b7cafc1dc` — `fix(private): recover VPN after task removal`
- `1e1cfb28c91442fc118eae36c0bd5ddd1a56c8af` — `fix(private): recover VPN after recent-task swipe`
- `dfcec7888cc4a6ca8ed3b832aa5839ab27417a58` — `fix(private): keep background services independent of task`

这类思路在本窗口后续被重新审视。

当前裁决：

**目标不是“用户把任务卡划掉以后无论如何都把 App 再拉起来”。**

真正目标是：

**只要 Penrix/VPN 处在应运行状态，网络数据面就应持续可用；发生切网、Doze、短暂断网后应能恢复。**

因此后续 `72ccedc` 的数据面健康恢复工作撤掉/不继续强化 Alarm 强拉活方向。

新窗口禁止把“划后台强复活”重新当主路线，除非未来有新的、明确的真机证据证明数据面问题根因就是 process lifecycle，并且现有 foreground/sticky/Always-on 机制不足。

---

# 6. 当前核心完成项：VPN 数据面健康恢复

commit:

`72ccedc589cd3b977e1db6c13a2088ccda8c8a52` — `feat(android): add VPN data-path health recovery`

这是当前 Android 可靠性路线的关键转向。

## 6.1 母问题

不是：

> App 进程是不是永远活着？

而是：

> VPN → TUN → Mihomo/Core → 真实 HTTP 数据面，在 VPN 应处于工作状态时是不是真的还能走通？如果断了，能否用最小恢复动作把它救回来？

## 6.2 已发现的 upstream 基础

FlClash 本身已经有两块基础，但以前没有闭成“真实数据面健康”回路：

1. 已监听 Wi‑Fi / cellular 等底层网络变化，并做 DNS 更新；
2. 已在 Doze / 唤醒时通知 Mihomo `OnSuspend` / `OnRunning`，唤醒后还能触发现有代理健康行为。

缺的不是“再监听一次”，而是：

**在关键事件之后确认整条 VPN 数据面真正可用，并在确认失效后进行有界恢复。**

## 6.3 恢复状态机

当前核心文件：

`android/service/src/main/java/com/follow/clash/service/VpnConnectionHealth.kt`

以及集成点：

`android/service/src/main/java/com/follow/clash/service/VpnService.kt`

当前语义：

- 单次探测失败：不动作；
- 连续失败阈值：`3`；
- 第一次达到阈值：`REBUILD_TUN`；
- TUN 重建后若恢复成功：记录 recovered，回到健康状态；
- TUN 重建后若再次连续 3 次失败：进入 `STUCK`；
- 进入 `STUCK` 后停止无限升级/无限重启，留下现场供下一层诊断。

这是刻意的 **bounded recovery**。

## 6.4 触发理念

健康检查围绕关键生命周期事件，而不是永久轮询：

- VPN 启动后；
- Wi‑Fi ↔ cellular 等网络变化后；
- 长时间休眠 / Doze 恢复后；
- 其他已经存在的关键恢复事件。

明确没有把以下方案作为当前设计：

- 永久 30 秒 ping；
- 常驻 WakeLock；
- 一次失败就重启；
- 无限 Core 重启；
- Alarm 定时把 App 拉起来。

## 6.5 `setUnderlyingNetworks()` 的裁决

本窗口专门检查过是否应该在底层网络变化时调用 Android `VpnService.setUnderlyingNetworks()`。

**当前决定：不加。**

原因不是“忘了”，而是当前 Mihomo/FlClash 的上游 socket 模式主要依赖 protected sockets 绕过 VPN，并没有建立“把 socket 显式 `Network.bindSocket()` 到某一条底层 `Network`”的对称架构。

Android 的 underlying-network 声明如果和实际 socket binding 语义不一致，可能让默认网络切换更复杂而不是更稳。

只有未来网络出口架构真正改成显式绑定具体 Android `Network` 时，再一起重新评估 `setUnderlyingNetworks()`。

---

# 7. 测试与 CI：当前真实状态

## 7.1 `72ccedc` 当时的状态

在数据面恢复刚落地时：

- Android JVM unit tests 已通过；
- 新增恢复状态机测试已通过；
- private Android Release 构建已通过并产出 APK；
- 当时完整 push workflow 仍有一个 Dart 全量测试失败，尚未彻底判定是否相关。

这个“Dart 测试仍失败”已经是**历史状态，不是当前 blocker**。

## 7.2 交接时 current HEAD 的状态

交接捕获 HEAD `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`：

- `build` workflow run #50：`success`
- `private-android-ci` run #42：`success`

因此：

**新窗口不得把 `72ccedc` 时那一个 Dart full-test failure 继续当成 unresolved current issue。**

后续 `cca32d9...` 等 commit 已经让当前完整 branch workflow 回到 green。

## 7.3 已交付的旧测试 APK

`72ccedc` 对应 Release APK 曾交付给用户：

- filename: `Penrix-72ccedc.apk`
- SHA-256: `a9882bc42b0817d821ce2f15fc722a72f93d65a1b3022238091ed6bd17584765`

注意：这不是交接 HEAD 的最终包，因为 HEAD 后面还有 app name / label / hotkey / private package isolation 5 个 commit。

新窗口若要再次给用户 APK，必须从当前 live HEAD 的 green artifact / current build 生成，不要把旧 `72ccedc` APK 冒充最新版本。

---

# 8. 真机验收：仍然 OPEN

这是当前最重要的未闭环。

CI green ≠ 用户 Android 真机稳定性已经证明。

需要在 **当前 live build** 上做四类实际场景：

1. 长时间锁屏 / screen-off / Doze 后，解锁直接联网；
2. Wi‑Fi → 5G/cellular；
3. cellular → Wi‑Fi；
4. 短暂完全断网后重新恢复网络。

观察重点不是“App 界面还在不在”，而是：

- 网络是否无感恢复；
- health probe 是否开始连续失败；
- 是否触发 `REBUILD_TUN`；
- rebuild 后是否出现 recovered；
- 是否进入 `STUCK`；
- 若 `STUCK`，是 TUN 层无效还是 Core/route/DNS/Android network 层更深的问题。

## 8.1 下一层恢复目前故意没有实现

如果真机证明：

> 重建 TUN 足以恢复

则不需要更重的恢复。

如果真机证明：

> `REBUILD_TUN` 后仍可靠复现 `STUCK`

才有证据进入第二级：考虑 **有界 Core 重建 / profile runtime 重建**。

禁止现在预先把“重启整个 Core”塞进去掩盖故障现场。

---

# 9. 不可恢复的错误方向 / Dead Ends

## 9.1 紧急广告拦截 commit 不得恢复

历史 bad commit：

`6e6e84293585dba264e2512cdfa9fed9865835a3`

已被 force-reset 掉。

**禁止恢复。**

原因：它属于过度/粗暴的 emergency adblock 方向，不符合后来形成的“网络层与内容层分工”架构。

## 9.2 不要把第一方原生广告问题全部压给 Mihomo domain REJECT

当前 private routing 中的 adblock RULE-SET / domain rejection 只作为网络层辅助。

它不能被宣传为：

- X 第一方 promoted post 的可靠消除方案；
- YouTube 原生视频广告/播放器 UI 的完整解决方案；
- Telegram Sponsored Messages 的完整解决方案。

这些应交给 app patch layer。

## 9.3 不要把 FlClash 改造成 Surge clone 才算成功

Surge 的 HTTPS MITM / URL rewrite / response mutation / script 能力属于另一层能力模型。

当前私人 FlClash 的价值在于：

- 稳定代理；
- 路由；
- DNS；
- diagnostics；
- Android VPN reliability；
- Windows network integration。

不要为了追求“所有东西都在一个 App 做”破坏这一层的简单性和稳定性。

---

# 10. Windows 并行路线

已有文档：

`docs/PENRIX-WINDOWS-LOCAL-NETWORK-AUDIT-CONTRACT.md`

关键 commit：

`8a2a24c84729cdcdc8258854031e347946be7ed3` — `docs(private): add Windows local network audit contract`

架构：

```text
Windows actual environment
  ↓
Windows Environment Doctor
  ↓
system proxy / WinHTTP / DNS / routes / IPv4/IPv6 / adapters /
WSL / Hyper-V / Docker / other VPN/proxy / firewall/WFP / loopback/UWP
  ↓
Penrix Private Policy
  ↓
proxy engine
```

当前裁决：

- 先做 read-only 环境诊断；
- 第一工作模式优先 System Proxy；
- 不盲改 TUN / route / DNS / firewall / WFP；
- TUN 等重操作前必须完成 admin-only reads；
- 任何系统改动应先 snapshot / rollback；
- portable-first；
- ChatGPT.exe 可以考虑 process rule；浏览器 ChatGPT 应依赖 domain/WebSocket，不 blanket proxy 全 Chrome/Edge。

此路线存在，但当前 Android 数据面可靠性是真机待验收的更近工作单元。

---

# 11. 其他 App patch 并行路线（只恢复边界，不抢当前主线）

## 11.1 YouTube

当前路线：Morphe 为主，吸收 Anddea / RVX 的高价值 UX 思路，不做 browser frontend。

用户明确痛点：

- 画质被藏在“高级”；
- 播放器手势差；
- pause / recommendation 的 `More videos` overlay 遮住 seekbar，影响拖动。

期望默认项包括：

- 视频/Feed/Premium 推销类广告 patch + SponsorBlock；
- 直接高级分辨率列表、默认高画质、可选播放器画质按钮；
- tap seekbar、按住左右滑 seek；
- 替代烦人的默认长按 2x / precise scrubbing；
- 左亮度 / 右音量；
- Hide `More videos`、end-screen/related overlays；
- 下载入口交给 YTDLnis，产出普通本地媒体文件；
- Return YouTube Dislike、original audio、disable DRC、sanitize share links 等作为高价值补丁候选。

稳定 pinned 版本优先于追 newest experimental。

尚未在本 repo 里实现该 App patch。

## 11.2 X / Twitter

路线：Piko NewX + Morphe，保留官方代码基底、账号/推荐/native UX。

不要承诺绝对 zero ads；已知 Explore 等位置可能仍需版本级验证。

尚未在本 repo 里实现。

## 11.3 Telegram

目标：

- sponsored messages 去除；
- content restriction 的 client-side bypass；
- download speed / native download usability。

候选 patch 需要先审计当前源码与兼容版本。

尚未实现。

---

# 12. 私人路由与站点层的已知背景

私人网络规则此前已覆盖/考虑：

- ChatGPT 专用路由；
- UAA direct；
- Twitter；
- Telegram；
- GitHub；
- Google；
- Pixiv；
- adblock RULE-SET（辅助层）；
- private sites；
- subscription/custom rules。

ViralPorn 已加入 private site routing：

`97f45007a459527315140ed305f941a92b1abd41` — `fix(private): include ViralPorn in private site routing`

不要因为 app patch 路线出现而删除这些网络层规则。

---

# 13. 用户已经明确纠正过的判断

以下不是“可选建议”，而是本窗口形成的约束：

1. **不要移除 FlClash 网络能力，只因为内容广告需要 App patch。**
2. **不要用浏览器替代原生 App 作为默认答案。** 用户要保留账号、推荐算法、历史、订阅、原生播放器/时间线体验。
3. **不要声称 domain block 能完整消掉第一方原生广告。**
4. **不要为了看起来更完整，盲加 `setUnderlyingNetworks()`。** 当前 socket-binding 架构不匹配。
5. **不要把 recent-task swipe 强拉活当当前主目标。** 当前目标是真实网络数据面连续可用。
6. **不要一次 health probe 失败就重启。** 当前是 3 连败阈值 + bounded recovery。
7. **不要无限重建 TUN / Core。** 进入 `STUCK` 要保留证据。
8. **不要在真机没验收前说“后台/切网问题已解决”。** CI 只能证明代码和测试链条。
9. **不要恢复 bad emergency adblock commit `6e6e842...`。**
10. **稳定 pinned build > 无休止追最新版。**

---

# 14. 当前 OPEN LOOPS，按优先级

## P0 — 真机验收当前 live Android build

四类场景：

- long lock / Doze；
- Wi‑Fi → cellular；
- cellular → Wi‑Fi；
- no-network → recovered network。

若用户在新窗口直接反馈“还是断”“切 5G 不通”“锁屏醒来不通”等，不要重新讨论抽象架构；先根据日志判断 health state / TUN rebuild / STUCK 落在哪层。

## P1 — 只有 P0 证明 TUN rebuild 不够时，设计第二级恢复

候选：bounded Core/runtime rebuild。

要求：

- 必须有明确触发条件；
- 有次数上限/冷却；
- 成功后 reset state；
- 失败后保留现场；
- 不变成 restart-everything loop。

## P2 — Android “后台可靠性”诊断页（候选，未实现）

未来可考虑展示：

- VPN service status；
- sticky state；
- battery optimization state + shortcut；
- Always-on VPN state/link；
- last process exit reason；
- current runtime / last recovery reason。

它是可观测性 UX，不是新的保活机制。

## P3 — Windows 环境诊断 / System Proxy 路线

在 Android 真机验收间隙可继续，但不要无授权进入 TUN/WFP/Firewall 修改。

## P4 — YouTube/X/Telegram patch apps

它们是并行产品工作，不应混进 FlClash core/network patch 中。

---

# 15. 恢复时必须验真的 repo anchors

新窗口不要只读本文件就相信代码没有变化。恢复后至少检查：

1. `penrix-private-network` 当前 branch HEAD；
2. 最新 GitHub Actions：`build` + `private-android-ci`；
3. `android/service/src/main/java/com/follow/clash/service/VpnConnectionHealth.kt`；
4. `android/service/src/main/java/com/follow/clash/service/VpnService.kt`；
5. `lib/common/penrix_android_dns.dart`；
6. `lib/providers/action.dart`；
7. `test/common/penrix_android_dns_test.dart`；
8. `docs/PENRIX-WINDOWS-LOCAL-NETWORK-AUDIT-CONTRACT.md`（只有 Windows 路线需要时）；
9. 当前 draft PR #1 状态。

如果 live state 与本 handoff 冲突：

- 代码/CI 的更新事实以 live state 为准；
- 本 handoff 中的产品裁决、用户纠正、dead ends 仍继续生效，除非后续 commit/document 明确推翻。

---

# 16. 新窗口最小恢复握手

完成 Manifest + 本 Handoff + live verification 后，新窗口应能直接形成以下工作状态：

> 我已恢复 `Penrix/FlClash` 的 `penrix-private-network` 私人网络分支。当前 Android 可靠性主线已经从“任务卡划掉后强拉活”转向“真实 VPN 数据面健康 + 有界 TUN 自愈”。`72ccedc` 已落地 3 连败→重建 TUN→再失败进入 STUCK 的恢复状态机；交接捕获时 branch 已推进到 `e4fa5c8`，并完成私人 Android package identity 收拢，最新 build 与 private Android CI 均为 green。当前真正未闭环的是四类真机稳定性验收；只有真机证明 TUN rebuild 仍不够，才进入 bounded Core recovery。DNS 7874、Android DEBUG ribbon、sticky foreground VPN 等修复都已经进入历史基线，不应回退。

然后直接接用户的新反馈或下一工作单元。

**不要重新向用户询问“这个项目要做什么”。**
