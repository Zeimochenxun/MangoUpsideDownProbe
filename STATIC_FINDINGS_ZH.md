# Mango 方向管线专项静态结论

分析对象：上传的 `mango(1).dylib`；SHA-256 `4679a2314e3a2f9e18d65503e5c69d67faaae81ab62b27d4d989a29b057f7ed6`；Mach-O UUID `67c0d7c2-4487-3fd2-9535-067745ae4b8f`；arm64e。以下地址均为未加 ASLR slide 的 Mach-O 虚拟地址。

## 结论先行

1. **已证实：Mango 能收到并保存 `PortraitUpsideDown=2`。** 旧运行日志反复出现稳定的 `mangoOrientation=2`。静态上，scene-settings 解析函数还为 `portraitUpsideDown` 设置了独立分支。
2. **已证实：Mango 的 SystemAperture 手势 Hook 把 1 和 2 放进同一个非横屏分支。** `sub_0xea7fc` 计算 `orientation - 3`，只有结果 `0/1`（原值 3/4）进入 landscape 分支，1/2 都落入同一条 portrait fallback。
3. **已证实：Mango 通知元素自己的 `handlePanGesture:` 完全不读取方向。** 手势结束时 `translation.y > 30` 调用 `defaultAction`；`translation.y < -30` 或 `abs(translation.x) > 50` 调用 `dismissWithContent:YES`。
4. 因此，通知岛上下语义反转的首要根因不是“获取阶段必然把 2 改成 1”，而是**手势消费层没有针对 2 转换语义**。是否还有瞬时的 2→1 状态抖动，需要本轮 Probe 继续记录；旧日志确实出现过少量短暂不一致，但稳定状态明确能达到 2。
5. 横屏分屏成功后的完整适配来自 `DecoratedAppSceneView` 等另一套 scene/layout 管线；启动热区属于 `ViewController launcherPanned:` / `launcherPannedRight:` 一侧，适合作为独立问题记录。

## 核心调用链

### 方向获取与保存

`-[SBDeviceApplicationSceneHandle(mango) mango_didUpdateClientSettingsWithDiff:transitionContext:]` (`0x9ca94`)

→ 在 settings diff 描述中查找 `interfaceOrientation` / `preferredInterfaceOrientation`

→ 依次识别 `landscapeRight`、`landscapeLeft`、`portraitUpsideDown`、`portrait`

→ 将独立整数对象传给 `sub_0x982dc`

→ Mango 全局方向值位于 `0x1746d0`

→ `+[DecoratedAppSceneView mango_currentInterfaceOrientation]` (`0x721d0`) 直接返回该全局值。

这条路径中 `portraitUpsideDown` 有独立比较和独立对象，不是简单的 `else portrait`。

### 通知岛手势路径 A：MangoPillElement

`-[MangoPillElement handlePanGesture:]` (`0xe8dac`)

→ `translationInView:` 得到 `d0=x, d1=y`

→ 仅处理 `state == 3`（Ended）

→ `y > 30.0` → `defaultAction`

→ 否则 `y < -30.0` 或 `fabs(x) > 50.0` → `dismissWithContent:YES`

→ 函数内没有读取 `mango_currentInterfaceOrientation`、`UIWindowScene.interfaceOrientation` 或 device orientation。

### 通知岛手势路径 B：Mango 对 SystemAperture 的 Hook

初始化函数 `sub_0xea3c4` 已证实执行：

`MSHookMessageEx(SBSystemApertureViewController, _handleResizePan:, sub_0xea7fc, &oldIMP)`

`sub_0xea7fc` (`0xea7fc`)

→ 读取 Mango 全局方向 `0x1746d0`

→ `orientation - 3`

→ `cmp ..., #1; b.hi`：只有 3/4 进入 landscape begin/cancel 处理，1/2 共用 fallback

→ Ended 时读取 `translationInView:`

→ `y > 30` 按 `pillSwipeDownAction` 打开全屏/分屏/回复

→ `y < -30` 按 `pillSwipeUpAction` 清除等

这里正好解释了：系统和 Mango 都可以报告 2，但 Mango 的通知手势仍沿用普通 Portrait 的上下语义。

## 最有价值的函数

| 地址 | 函数 | 调用/被调用重点 | 已证实职责 | 置信度 |
|---:|---|---|---|---|
| `0x721d0` | `+[DecoratedAppSceneView mango_currentInterfaceOrientation]` | 读取 `0x1746d0` | Mango 当前方向 getter | 极高 |
| `0x9ca94` | `mango_didUpdateClientSettingsWithDiff:transitionContext:` | 字符串解析 → `sub_0x982dc` | scene diff 到 Mango 方向的输入路径 | 高 |
| `0xea3c4` | 未命名初始化函数 | `MSHookMessageEx` | 安装 SystemAperture/Mango 通知相关 Hook | 极高 |
| `0xea7fc` | 未命名 replacement | `_handleResizePan:` 原 IMP、Mango actions | SystemAperture 手势消费及 3/4 vs 1/2 分支 | 极高 |
| `0xe8dac` | `-[MangoPillElement handlePanGesture:]` | `translationInView:` → actions | Mango 通知元素上下/横向手势阈值 | 极高 |
| `0xe8a14` | `-[MangoPillElement setLayoutMode:reason:]` | 更新 layout mode | Mango pill mode 变化入口 | 高 |
| `0xe5118` | `preferredEdgeOutsetsForLayoutMode:...` | 读取 `0x1746d0` | pill outsets；仅 3/4 走横屏路径 | 高 |
| `0xe963c` | `-[MangoPillManager handleInterfaceOrientationChange:]` | 遍历 active pills → dismiss | 方向变化时清理活动 pill，不做方向归一化 | 高 |
| `0xd4798` | `-[ViewController mango_updateLauncherRotation]` | getter → 3/4 分支 → rotation | launcher 仅为横屏构造旋转 | 极高 |
| `0xdb904` | `-[ViewController swapLauncherViewsForOrientation]` | getter → 3/4，否则返回 | 横屏 launcher 左右交换 | 极高 |
| `0xcc950` | `-[ViewController launcherPanned:]` | location/state/layout | 左侧分屏启动手势 | 高 |
| `0xcdc5c` | `-[ViewController launcherPannedRight:]` | location/state/layout | 右侧分屏启动手势 | 高 |
| `0x7a90c` | `sceneInterfaceOrientationDidChange:` | scene orientation / layout | 分屏 scene 方向适配入口 | 高 |
| `0x7acac` | `adjustWindowForSceneOrientationChange:isLandscape:` | window geometry | 分屏窗口方向调整 | 高 |
| `0x88670` | `applySplitLayoutMode:animated:` | split layout | 分屏布局模式应用 | 高 |

## 四方向当前证据

| 方向 | UIWindowScene | Mango getter | Mango pill 分支 | 当前结论 |
|---|---:|---:|---|---|
| Portrait | 1 | 1 | portrait fallback | 基线正常 |
| PortraitUpsideDown | 2 | 旧日志已证实可为 2 | **仍为 portrait fallback** | 上下手势语义错误的直接证据 |
| LandscapeLeft | 3 | 待新日志成组确认 | landscape | 分屏成功后已由用户确认完整适配 |
| LandscapeRight | 4 | 待新日志成组确认 | landscape | 分屏成功后已由用户确认完整适配 |

`MangoPillElement.handlePanGesture:` 比表中更简单：四个方向都执行同一组 y/x 阈值，没有任何方向分支。

## 下一修复点排序

1. **优先候选：只修 Mango 的通知手势语义。** 运行日志确认实际经过 `_handleResizePan:` 或 `MangoPillElement.handlePanGesture:` 后，在 orientation=2 时于最小范围转换其局部判定；不能全局修改 `UIPanGestureRecognizer`。
2. 如果实际动作全部来自 Mango 的 `_handleResizePan:` replacement，则应围绕这个已确认的入口设计兼容 Hook，并保持 1/3/4 完全原样。
3. 如果实际动作来自 `MangoPillElement.handlePanGesture:`，则可只 Hook 这个真实方法；但必须避免同时补偿两条路径导致双重反转。
4. 不建议伪造 Mango getter 返回 3/4：横屏分支还会触发布局、begin/cancel 和 launcher 逻辑，可能造成视觉/触摸副作用。也不应把 2 返回成 1，因为当前问题正是 1/2 共用语义。
5. 分屏热区单独处理：先用 `[SPLIT-ACTIVATION]` 比较 3/4 下 gesture view bounds 与起点，再判断是 recognizer view/frame、固定边缘还是 activation rect 写死。

## Probe 的验证目标

- `[MANGO-ORIENTATION-INPUT] token=portraitUpsideDown` 后 getter 是否稳定为 2。
- `[MANGO-GESTURE] path=... orientation=2 branch=portraitFallback` 是否与错误动作同一次 event 对应。
- 实际动作到底由哪条入口触发，避免未来双 Hook。
- `layoutMode` 在 1/2/3/4 是否变化；注意 layoutMode 是 SystemAperture 展示模式，不一定等价于 interface orientation。
- 横屏分屏启动时 `[SPLIT-ACTIVATION]` 的 `viewBounds` 和触点是否仍保持竖屏坐标基准。
