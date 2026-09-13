# Window Recovery Manifest 001 — FlClash / Penrix Private Network

- `window_id`: `WIN-20260912-FLCLASH-PRIVATE-NETWORK-001`
- `transfer_id`: `HANDOFF-WIN-20260912-FLCLASH-PRIVATE-NETWORK-001-001`
- `transfer_type`: `whole-window blind transfer`
- `scope`: `full`
- `repository`: `Penrix/FlClash`
- `working_branch`: `penrix-private-network`
- `source_repo_commit_at_capture`: `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`
- `source_tree_at_capture`: `6e9f96fe08902b8fa8a14b6394c6b90638915c05`
- `capture_date`: `2026-09-13`
- `manifest_role`: `oversight / verification layer`
- `primary_semantic_payload`: `WHOLE-WINDOW-HANDOFF-CHECKPOINT-001.md`

> 本 Manifest 不是项目摘要。它负责规定新窗口的读取顺序、验真步骤、语义库存与恢复完成条件。
>
> 不要只读 Manifest 就开始工作；必须继续读 Handoff。

---

## 1. Blind Recovery 读取顺序

新窗口必须按以下顺序恢复：

1. `working/session-continuity/windows/WIN-20260912-FLCLASH-PRIVATE-NETWORK-001/WINDOW-RECOVERY-MANIFEST-001.md`
2. `working/session-continuity/windows/WIN-20260912-FLCLASH-PRIVATE-NETWORK-001/WHOLE-WINDOW-HANDOFF-CHECKPOINT-001.md`
3. 验真 `penrix-private-network` 当前 branch HEAD，不得假设仍停在 capture SHA。
4. 验真当前 branch 最新 GitHub Actions，至少看：
   - `build`
   - `private-android-ci`
5. 根据用户下一条反馈，按需读取 Handoff 第 15 节列出的 repo anchors；不要无目的遍历整个仓库。
6. 若 live repo 产生了 capture 后的新 commit：
   - 代码与 CI 的更新事实以 live state 为准；
   - Handoff 中的用户裁决 / 产品边界 / dead ends 默认继续生效，除非有明确后续文档或 commit 推翻。

---

## 2. 恢复类型判定

这是：

**Whole-Window Blind Transfer / Session Continuation**

不是：

- Fresh Onboarding；
- 项目介绍；
- 从 main 重新理解 upstream FlClash；
- 重新设计私人网络架构；
- 仅恢复最后一条消息；
- 从记忆猜测旧窗口发生过什么。

目标：

**恢复到旧窗口已经可以继续工作的语义现场。**

---

## 3. Required Artifacts

### 必需

1. `WHOLE-WINDOW-HANDOFF-CHECKPOINT-001.md`
   - 主语义载荷；
   - 包含产品坐标、技术裁决、完成项、失败方向、测试状态、开放循环、下一步。

2. `WINDOW-RECOVERY-MANIFEST-001.md`
   - 本文件；
   - 负责读取协议、库存核对和恢复验收。

### 当前仓库特别说明

在本次交接之前，`Penrix/FlClash` 的 `penrix-private-network` branch **没有**自己的 `.hermes.md` 或 `working/session-continuity` 目录。

本次采用的是 Penrix 现有仓库已经运行的 Session Continuation / Whole-Window Blind Transfer 同构标准，并首次在 FlClash 私人分支落地这两份恢复工件。

因此新窗口不要寻找一个并不存在的旧 FlClash `.hermes.md` 再宣称“协议缺失”。

---

## 4. Semantic Branch Inventory

恢复完成前，以下语义字段必须全部在新窗口工作记忆中成立：

### A. 产品与架构

- `network_layer_role`
- `app_patch_layer_role`
- `no_root_android_constraint`
- `stable_pinned_build_preference`
- `native_ux_preference`

### B. Android 已完成修复

- `debug_banner_root_cause_and_fix`
- `dns_7874_root_cause_and_sanitizer`
- `sticky_foreground_vpn_baseline`
- `vpn_data_path_health_recovery`
- `private_android_package_identity`

### C. Android 可靠性当前路线

- `mother_problem_real_data_plane_availability`
- `event_triggered_health_checks`
- `three_failures_threshold`
- `bounded_tun_rebuild`
- `stuck_terminal_state`
- `no_infinite_restart`
- `no_alarm_force_revival_as_primary_strategy`
- `no_setUnderlyingNetworks_without_matching_socket_binding`

### D. CI / 证据状态

- `capture_head_e4fa5c8`
- `build_run_50_success`
- `private_android_ci_run_42_success`
- `old_dart_failure_is_stale`
- `real_device_acceptance_still_open`

### E. Dead Ends / Guards

- `never_restore_6e6e842_emergency_adblock`
- `do_not_overclaim_domain_adblock`
- `do_not_merge_app_patch_layer_into_flclash`
- `do_not_use_browser_replacement_as_default`
- `do_not_claim_real_device_fix_before_test`

### F. Parallel tracks

- `windows_environment_doctor_and_system_proxy_first`
- `youtube_morphe_track`
- `x_piko_newx_track`
- `telegram_patch_audit_track`

### G. Open loops

- `android_four_scenario_device_test`
- `diagnose_logs_if_failure`
- `bounded_core_recovery_only_if_tun_rebuild_proven_insufficient`
- `optional_background_reliability_diagnostics_page`

---

## 5. Source-State Verification Anchors

Capture 时的 branch source anchor：

`e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`

message：

`chore(android): register private package ids`

其 parent：

`7aa78e32b3edbc6c27b3c034ab3ec67beaf773c8`

Capture 时 source tree：

`6e9f96fe08902b8fa8a14b6394c6b90638915c05`

### `72ccedc` → capture HEAD 的 5 commits

1. `3b7ed323e4335a074f1018f345f5d08df772486a`
2. `ed7afb83a7461930816df6871a5cc6611e6bb048`
3. `cca32d9e6060711483a5f8dd69195db9cfe59bc9`
4. `7aa78e32b3edbc6c27b3c034ab3ec67beaf773c8`
5. `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`

Compare 结果：`ahead_by = 5`, `behind_by = 0`。

---

## 6. CI Verification Snapshot

交接捕获时：

### Private Android CI

- workflow: `private-android-ci`
- run number: `42`
- run id: `34727838268`
- head SHA: `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`
- status: `completed`
- conclusion: `success`

### Full Build

- workflow: `build`
- run number: `50`
- run id: `34727836291`
- head SHA: `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a`
- status: `completed`
- conclusion: `success`

### 旧信息清理

在 `72ccedc` 刚完成时，曾有一个 Dart 全量测试失败尚未查清。

**Capture 时已经不能把它当 current failure：当前 HEAD 的完整 build 已 success。**

新窗口若仍把“Dart test pending”当 blocker，说明恢复失败或读取了过期上下文。

---

## 7. Critical Code Anchors

只在需要验真具体实现时读取：

### Android health / service

- `android/service/src/main/java/com/follow/clash/service/VpnConnectionHealth.kt`
- `android/service/src/main/java/com/follow/clash/service/VpnService.kt`

### DNS sanitation

- `lib/common/penrix_android_dns.dart`
- `lib/providers/action.dart`
- `test/common/penrix_android_dns_test.dart`

### Android private package / labels

- `android/app/build.gradle.kts`
- `android/app/google-services.json`
- `android/common/src/main/res/values/strings.xml`
- `lib/common/constant.dart`

### Windows track

- `docs/PENRIX-WINDOWS-LOCAL-NETWORK-AUDIT-CONTRACT.md`

---

## 8. Commit Anchors That Must Not Be Misread

### Active baseline / good history

- `05e30c8a55c719662e08fe646e4e7317626a99a9` — sticky VPN service baseline
- `109a4afe522d989fe167ab1cc686fba525dc58cd` — Android DEBUG ribbon fix
- `7f4b156ca1e39ba7e2b37386a19a2939bd0d4f93` — DNS listener suppression scoped to Android VPN/TUN
- `72ccedc589cd3b977e1db6c13a2088ccda8c8a52` — data-path health recovery
- `e4fa5c8e0b0bbfa47804ad82386562fa3040a22a` — capture HEAD / private package ids

### Historical experiments, not current strategic target

- `ef2c88fe33c179b1e921448dd518cd4b7cafc1dc`
- `1e1cfb28c91442fc118eae36c0bd5ddd1a56c8af`
- `dfcec7888cc4a6ca8ed3b832aa5839ab27417a58`

These relate to task-removal / recent-task swipe / background service experiments. Current direction is data-path health, not “always force revive after swipe”.

### Explicitly forbidden to restore

- `6e6e84293585dba264e2512cdfa9fed9865835a3`

Bad emergency adblock commit; force-reset away.

---

## 9. Evidence Classes

新窗口恢复时必须保留以下 evidence boundaries：

### Repo-backed / implemented

- DEBUG banner Android private suppression；
- DNS listen sanitizer；
- sticky foreground VPN service；
- VPN data-path health state machine；
- private package/app identity commits；
- Windows audit contract；
- ViralPorn private routing。

### CI-backed

- capture HEAD `e4fa5c8` 的 `build` #50 success；
- capture HEAD 的 `private-android-ci` #42 success。

### Previously tested artifact, but not latest HEAD

- `Penrix-72ccedc.apk`
- SHA-256: `a9882bc42b0817d821ce2f15fc722a72f93d65a1b3022238091ed6bd17584765`

### Not yet user-device-proven

- long lock / Doze reliability；
- Wi‑Fi ↔ cellular transition reliability；
- no-network → recovery reliability；
- whether TUN rebuild alone is sufficient in all observed failures。

### Proposal only / future candidate

- bounded Core/runtime second-stage rebuild；
- Android 后台可靠性诊断页；
- YouTube/X/Telegram patched-app deliverables。

---

## 10. Resume Decision Tree

### 如果用户新窗口第一条就是“这个版本测试结果……”

直接进入真机证据分析，不做 Fresh Onboarding。

按顺序问自己：

1. 当时 underlying network 是否变化/validated？
2. health probe 是否连续失败？
3. 是否到 3 次阈值？
4. 是否触发 TUN rebuild？
5. rebuild 后 recovered 还是 STUCK？
6. 若 STUCK，下一层最可能是 Core/runtime、DNS、route 还是 Android network state？

除非日志确实不够，否则不要第一反应要求用户重装、清缓存、重启手机。

### 如果用户说“继续做稳定性”但没有新真机反馈

先确认 current HEAD / CI；然后优先增强 **observability / log extraction / acceptance workflow**，而不是先加更重恢复。

### 如果用户要求最新 APK

- 不给 `72ccedc` 旧 APK 冒充 latest；
- 从 current green HEAD 对应 artifact/build 获取；
- 明确 commit SHA、build/run、hash；
- 若 package isolation 导致可与官方 FlClash 共存，应以 live manifest/package id 验证后再描述。

### 如果用户转向 Windows

读 Windows Audit Contract，延续 System Proxy first / read-only first；不要跳到 TUN/WFP。

### 如果用户转向 YouTube/X/Telegram

保持 app patch layer 与 FlClash network layer 分离；不要把需求塞回 Mihomo core。

---

## 11. Recovery Acceptance Criteria

新窗口只有在可以不看旧聊天、直接回答以下问题时，才算恢复完成：

1. Penrix FlClash 在整个私人体系里负责哪一层？
2. 为什么 DEBUG 角标不是 Flutter 默认 banner？
3. `0.0.0.0:7874` 的真正来源是什么，为什么只在 Android+TUN 去掉 `dns.listen`？
4. sticky foreground VPN 与“Alarm 强拉活”有什么区别？
5. 为什么当前主问题从“App 活着”变成“数据面活着”？
6. health recovery 的阈值、TUN rebuild、STUCK 分别是什么？
7. 为什么当前没有加入 `setUnderlyingNetworks()`？
8. capture HEAD 是什么？最新两个 CI 在 capture 时是什么状态？
9. `72ccedc` 时的 Dart failure 为什么不能继续当 current blocker？
10. 真机还缺哪四类验收？
11. 什么证据出现后才允许设计第二级 Core recovery？
12. 哪个 bad commit 明确禁止恢复？
13. Windows 当前为什么是 System Proxy / read-only first？
14. YouTube/X/Telegram 为什么属于 app patch parallel track，而不是 FlClash core？

只要其中任何一项答不出来，应继续读 Handoff / live anchors，而不是让用户重述。

---

## 12. Minimal Blind-Start Instruction

如果新窗口只收到一句：

> 这是旧窗口的 Session Continuation Recovery，按仓库恢复。

则应：

1. 打开 `Penrix/FlClash`；
2. 使用当前 `penrix-private-network`；
3. 读取本 Manifest；
4. 读取 `WHOLE-WINDOW-HANDOFF-CHECKPOINT-001.md`；
5. 验真当前 HEAD + `build` + `private-android-ci`；
6. 恢复上述 Semantic Branch Inventory；
7. 直接继续用户当前工作，不做项目介绍，不让用户重讲旧窗口。

这就是本窗口的合法续接入口。
