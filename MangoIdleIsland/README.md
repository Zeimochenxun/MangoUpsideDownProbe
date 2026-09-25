# MangoIdleIsland 1.1.0

适用环境：iPhone 13 mini、iOS 16.5.0、Dopamine RootHide、arm64e、SpringBoard、Mango 约 1.0-Beta7-1。

1.1.0 的目标是让「灵动岛玻璃调整」真正成为 **Mango Island 材质域的统一参数入口**：只作用于 `filterType=go.mangoos.island`，同时覆盖 MangoIdleIsland 创建的静止态玻璃与 Mango 自己管理的通知、Live Activity、展开及其他 SystemAperture 活动态玻璃。

## 核心变化

### 使用 Mango 完整参数重载链

设置页仍写入 `com.go.mangoosprefs`，但不再把“写入偏好”等同于“renderer 已更新”。Beta7-1 静态调用链确认：

`com.go.mangoosprefs/Reload`
→ MangoOSRendering 重读参数缓存
→ `go.mangoos/ParametersReloaded`
→ 已存在的 `MGLiveBackdropView` reapply

因此 1.1.0 在设置保存后首先发布 `com.go.mangoosprefs/Reload`，由 MangoOSRendering 自己完成缓存失效/重读，再进入 Mango 原生 live-filter 刷新链。

### Active glass 原位刷新，不重建

Mango Active 状态已有自己的 `MGLiveBackdropView`。1.1.0 不删除、不替换、不覆盖第二个完整玻璃，也不接管 SystemAperture/MangoPillElement/MangoPillManager 生命周期。

插件会观察 `MGLiveBackdropView.reapplyFilterForParameterReload`。收到 `go.mangoos/ParametersReloaded` 后：

- 若对应 `go.mangoos.island` Active glass 已被 Mango 原生 reapply，记录 `observed-mango-refresh`，不重复处理；
- 若没有观察到 reapply，且运行时签名严格匹配 `void/no-args`，只对这个**现存 Active 对象**调用同一个 Mango 原生 selector，记录 `invoked-fallback`；
- selector 不存在或签名不匹配则不冒险，记录 `no-safe-runtime-refresh`。

绝不通过 `removeFromSuperview` 或重新 `initWithFrame:` 重建 Mango Active glass。

### Idle glass 继续 fresh-init

已知 Beta7 在 MangoIdleIsland 自己创建的 Idle `MGLiveBackdropView` 上，部分参数（尤其 Blur）原位 reapply 可能导致玻璃暂时消失，Respring 后才恢复。因此 Idle 仍沿用 1.0.1 的安全策略：只删除**属于 MangoIdleIsland 的 Idle 背景**，再以 `groupName=Island`、`filterType=go.mangoos.island` 创建新实例。

### 严格按 Island filterType 限定

所有新增 global-Island 逻辑都以 `lgFilterType == go.mangoos.island` 为准，而不是判断“是不是我们自己的 Idle view”。这使参数覆盖 Idle + Active Island glass，同时避免修改 Mango 的 Clock、CoverSheet 或其他 glass domain。

### 不制造双层全强度玻璃

原有 Idle/Active handoff 保留：Idle backing 根据 Mango-owned Island glass 的实际有效 opacity 衰减；Active 完全可见后 Idle 接近 0。仍保留约 60 ms 的首次提交过渡保护，避免切换第一帧空白。1.1.0 进一步把活动玻璃检测收紧为真正的 `go.mangoos.island`。

## 设置映射

- 色调通透 → `Island.Blur`（0–3，界面默认约 1.7）
- 色调强度 → 修改 `Island.LightTintColor` / `Island.DarkTintColor` 各自 RGBA alpha（0–1），**保留两套 RGB**；清除旧 `Island.TintStrength` 标量
- 边缘光 → `Island.SpecularEnabled`
- 边缘光调整 → `Island.SpecularOpacity`（0–1）
- 光斑 → `Island.DispersionEnabled`
- 光斑强度（全局）→ `Global.DispersionStrength`（0–20）

`Global.DispersionStrength` 确实是全局键，因此仍明确标为“全局”。虽然二进制存在 `.DispersionStrength` 后缀线索，1.1.0 不在缺乏足够证据时擅自写入所谓 `Island.DispersionStrength`。

## Tint 与 Active 自适应颜色

Beta7-1 中可见 `lg_updateTint`、`traitCollectionDidChange:`、`userInterfaceStyle`、`resolvedColorWithTraitCollection:` 等路径，说明 Active glass 存在 trait/style 感知的 tint 更新机制。

1.1.0 不把 Light/Dark 强制改成同一种颜色，也不叠加固定 UIKit tint。色调强度只修改当前 Light 和 Dark 色值各自的 alpha，保留它们原有 RGB 差异，以尽量不破坏 Mango 已存在的自适应链。

静态分析尚不能证明 wallpaper luminance 是否直接决定 Light/Dark 选择，因此该部分必须以实机视觉测试为准。详见 `STATIC_ANALYSIS_1.1.0.md`。

## 诊断日志

日志：`/var/mobile/Library/Logs/MangoIdleIsland/Status.log`

参数更新时新增：

```text
[PARAMETERS] notification=go.mangoos/ParametersReloaded generation=...
[PARAMETERS] generation=... island-glass-count=2 idle=1 active=1
[ISLAND-GLASS] owner=idle ...
[ISLAND-GLASS] owner=active ...
[GLASS-REFRESH] owner=active method=reapplyFilterForParameterReload result=observed-mango-refresh
[GLASS-REFRESH] owner=active method=reapplyFilterForParameterReload result=invoked-fallback
[GLASS-REFRESH] owner=active result=no-safe-runtime-refresh
[GLASS-REFRESH] owner=idle method=fresh-init result=rebuilt
```

不会每帧记录参数日志。

## 性能与安全边界

- 单一 MangoIdleIsland tweak，不新增“修复插件的修复插件”。
- 仅注入 SpringBoard。
- 不修改 Mango 原始 dylib，不 patch 固定地址。
- 不触碰 orientation、触摸、手势或 hit testing。
- 不使用 `MSHookFunction`。
- 500 ms fallback scan 保留，只扫描 SystemAperture 相关窗口且每棵树最多 256 节点。
- DisplayLink 仍只在状态过渡后短时以 30 fps 运行约 1 秒，随后暂停。
- 参数 refresh 为事件驱动；快速重复通知通过 generation 合并，避免反复重建 Idle glass。

## 实机验收

安装 1.1.0、Respring，等待插件初始化后依次测试：

1. 无活动时调整“色调通透”，Idle Island glass 应变化。
2. 触发通知或 Live Activity，再调同一项，Active Mango glass 应变化。
3. 调 Tint：Idle 与 Active 都应响应；Active 原有背景颜色/明暗自适应不能被彻底抹掉。
4. 开/关边缘光：Idle 与 Active 应统一。
5. 调整边缘光强度：Idle 与 Active 应统一。
6. 开/关光斑及调整全局光斑强度，观察两种状态。
7. 反复 Idle → Active → Idle：不得出现双层全强度玻璃、重复边缘光、永久空白、玻璃消失或残留 View。
8. 快速连续改参数：不得 SpringBoard crash / safe mode，CPU 不应长期异常。

正常情况下 Active 应优先出现 `observed-mango-refresh`。如果大量出现 `invoked-fallback`，说明 Mango 原生 observer 在目标设备/状态下没有按静态链预期触发，应以日志继续定位，而不是重建 Active glass。

## 恢复

若安装后 SpringBoard 循环崩溃：重启设备，在 Dopamine 关闭 tweak 注入后重新越狱，再从 Sileo 卸载 `com.chenxun.mangoidleisland`，之后再恢复注入。不要删除或替换 Mango 原文件。

仅需临时停用显示且 Filza 可用时，可在 `/var/mobile/Library/Logs/MangoIdleIsland/` 创建空文件 `DISABLED`；约一个 fallback scan 周期后插件停止更新自己的 Idle 背景。删除该文件可恢复。

## 构建

RootHide Theos + iPhoneOS16.5 SDK + Apple Clang：`make package FINALPACKAGE=1`。

构建约束：`ARCHS=arm64e`、`THEOS_PACKAGE_SCHEME=roothide`、SpringBoard-only。CI 会运行 `tools/check_package.py`、检查 arm64e Mach-O、依赖并上传 `MangoIdleIsland-1.1.0-RootHide` artifact。

静态验证和 CI 成功不等于完成实机验收；Active adaptive tint、各 SystemAperture 状态的实际 refresh、视觉交接仍需目标 iPhone 13 mini 验证。
