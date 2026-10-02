# Beta8 方向模块适配

整合包版本：`1.1.0~beta8.3`，完整文件：`MangoSuite-1.1.0-Beta8.3-RootHide-arm64e.deb`。本次稳定性修复的 CI 与成品检查待完成，手机验证仍待完成。

适用基线是用户提供的 RootHide Mango `1.0-Beta8-1`，iPhone 13 mini、iOS 16.5。用户已经在正常授权的原版上验证外部写入 `LeXiang.UpsideDown.Enabled` 可以开启原生倒置。本目录的方向模块不写这个偏好，不修改 Mango 文件或授权。

## 已确认的差异

旧 Suite 输入 `World 1.2.0`、`Split 0.1.1-alpha2` 围绕 `mango.dylib` 编写。Beta8 将 `MangoPillElement`、`DecoratedAppSceneView` 和 `DecoratedFloatingView` 放在 `MangoHello.dylib`。原倒置支持位在 `MangoPanda.dylib`，它和布局/手势模块职责分开。因此不能只把旧 guard 的 UUID 换成 Panda UUID。

| 证据 | Beta8 |
|---|---|
| MangoHello UUID | `15D63429-C2F1-3997-B6A2-3E0F803D8FED` |
| MangoPanda UUID | `05FEE465-833B-3982-AC57-CC721F1DA2E5` |
| scene 当前方向 getter | `+[DecoratedAppSceneView mango_currentInterfaceOrientation]`，`q16@0:8`，`0x4e4514` |
| pill 布局回调 | `layoutHostContainerViewDidLayoutSubviews:`，`v24@0:8@16`，`0xb4b870` |
| pill 自身 pan | `handlePanGesture:`，`v24@0:8@16`，`0xb7e16c` |
| 分屏 scene 布局 | `adjustWindowForSceneOrientationChange:isLandscape:`，`v28@0:8q16B24`，`0x544004` |
| 原 System Aperture resize-pan replacement | `0xba069c`，构造函数 `0xb9b8c0` 动态注册 `_handleResizePan:` |

Beta8 的 resize-pan 仍将方向 1/2 放到相同 portrait 分支，Ended 时使用原 `translationInView:` 的 y 做正负 30 的动作判断，没有方向 2 的显式 y 反转。旧 World 1.2.0 二进制 `0xef98` 的增量只是在这个调用内临时反转 Ended 的 translation.y，并在返回/异常时恢复。新模块保留这项行为，但额外要求 **World 实际拥有该手势所在岛窗口的半转**；原生窗口已经倒置、World 没有施加变换时不做补偿。

## 成品源码职责

- `Beta8Identity.h`：同时确认两个原版镜像 UUID、Mango 声明类来源和实际方法 ABI。独立的设置/加载器开关不被当作 Mango 授权结果。
- `World.m`：保留 iOS 16.5 上原 System Aperture window 半转、content 归一化、有限 hit-test 回退和倒置方向锁定。已有倒置 basis 不再施加第二次半转。删除旧诊断浮窗、全局 pan/velocity hook、只读长按 probe 和每次显式锁定的日志。
- `WorldPlacement.m`：仅修正由 Mango 布局回调确认的 container。保持弱引用 pending hosts、30 秒期限、64 项上限；实际窗口已经倒置且容器仍在错误物理边缘时才平移。
- `XiaoMang.m`：Beta8.2 新增，编入同一个 World target，与系统灵动岛共用“倒置方向与小芒修复”开关和 World 停用标记。只处理经 Panda 身份和方法 ABI 校验的 `XMFloatingWindow` / `XMPortraitVC` 组合；覆盖悬浮球、根面板、独立通知泡／卡片及相同类提示窗。小窗口也围绕物理屏幕中心变换；保留原生局部布局、手势和空白 hit-test。补偿倒置时，外层几何直接落在最终位置，保留独立子视图和透明度动画；不承诺所有原生窗口位置动画完全保留。详细范围与待验证的动画衔接见 [XIAOMANG.md](XIAOMANG.md)。
- `Split.m`：重新实现旧 Split 的纯 UIWindow 分屏作用范围。先识别 Mango 子视图、全屏形状、中心 anchor 和实际 coordinate-space basis；窗口已经倒置时不改。使用关联状态记录自己写入的 before/after，只恢复确实由自己写过且当前仍匹配的变换。原生或其他布局写过的半转不被旧版“见到 π 就清回 identity”的逻辑覆盖。
- **Beta8.3：** `SplitReconcile.h` 每次复查实际基底，处理匹配的 model 之上新增原生半转、外部 reset 与几何变化后的恢复；增加经原镜像／ABI 校验的启动器旋转与布局回调。`WorldPersistence.h` 同时验证 window/root 实际基底，保留稳定变换，纯布局事务不再暂时恢复未补偿的动画 model。外部替换先释放旧归属，满足完整几何守卫后才允许重新修正。
- `OrientationPolicy.h` 在 Mango cached portrait/unknown 与系统状态栏倒置读数不一致时补充方向信号，不永久锁定倒置，不修改 Mango getter。手势补偿只接受 Mango 的 portrait 1/2 分支，并要求 World 真正拥有当前物理倒置的 window/root；原生或其他来源的半转不被当作本插件所有权。
- `WorldMath.h`、`Geometry.h`：共享实际数学运算。`MWOwns` 明确区分当前矩阵相同与真正拥有该矩阵。
- `XiaoMangGeometry.h`、`XiaoMangMutation.h`：分别计算不同 scene 父坐标下的物理屏幕半转，以及同一窗口嵌套几何 setter 的单次恢复／重算事务。已经由原生倒置的实际 basis 不再翻转；恢复只针对仍匹配本插件记录的变换。
- `XiaoMangAnimation.h`：仅清理当前被镜像或本插件拥有的窗口外层 `position`、`bounds`、`transform` 属性动画及纯几何动画组，避免先前外层动画的 presentation 端点与新镜像模型不一致。透明度、混合动画组和所有子层动画保留。

所有回调在主线程上改变 UIKit 几何。停用标记兼容原路径和 RootHide 映射路径。载入阶段允许 20 秒等待原 Mango 镜像/类注册，运行期间不卸载已挂钩的方法。

## 构建与验证

World target files：`World.m WorldPlacement.m XiaoMang.m`。
Split target files：`Split.m`。
框架：Foundation、CoreFoundation、UIKit、QuartzCore。
库：substrate、roothide。
编译：arm64e、iOS 16.5 SDK、RootHide、ARC、blocks。

`tests/world_math_test.c` 直接调用成品 `WorldMath.h`，覆盖 375×812 物理屏幕、非中心/缩放窗口半转、归一化、原生半转没有所有权、外部写入后所有权失效。`tests/placement_test.c` 直接调用 `Geometry.h`，沿用已捕获的真机几何，检查 10000 次调和不累积、父坐标反变换、尺寸变化和拒绝条件。`tests/pan_correction_test.m` 直接调用成品 `PanCorrection.h` 的同步临时修改函数，在 macOS Foundation 上验证临时只反转 y、原回调仅一次、正常返回与原回调异常时恢复、恢复 setter 异常时递归计数仍归零。它不模拟 UIKit 的坐标转换。

`tests/xiaomang_geometry_test.c` 直接调用 `XiaoMangGeometry.h`，使用独立的正向坐标模型验证 260×260 主窗、偏中心通知小窗、父 scene 缩放／平移和旋转补偿、物理三点／角点镜像、布局更新、已有原生倒置与无效输入；局部拖动方向检查只验证几何模型，不模拟真实 UIKit 手势。`tests/xiaomang_mutation_test.m` 直接调用 `XiaoMangMutation.h`，检查原回调读取原生基线、嵌套 setter 仅外层恢复／重算，以及恢复、原回调、完成回调异常后计数释放。`tests/xiaomang_animation_test.m` 直接调用 `XiaoMangAnimation.h`，使用真实 QuartzCore layer 检查外层几何属性与纯几何组的清理，同时保留 fade、混合组和子层 fly-in。

Beta8.2 上述六项 helper、Objective-C 编译和最终包检查已有 CI [36985749665](https://github.com/Zeimochenxun/MangoUpsideDownProbe/actions/runs/36985749665) 记录，仅证明旧版。Beta8.3 新增共享方向策略、World 持续修正和 Split 调和回归；本次 macOS CI、arm64e 构建和最终包检查待完成，完成后以交付目录的真实记录为准。这些检查不模拟 UIKit 真机行为。

## 证据与来源

本地旧 Split 源码从 [exact source commit](https://github.com/Zeimochenxun/MangoUpsideDownProbe/tree/1a376ee74bdb480d5b1e918343e8dad7205f9971) 只读获取。World 的基础几何源码来自 [integrated placement commit](https://github.com/Zeimochenxun/MangoUpsideDownProbe/tree/04833c037e76e43f8e403d774054b16cbec92b8c)，此 commit control 为 **1.1.0**；没有冒称它就是 1.2.0 源码。1.2.0 的最小 pan 修复直接依据原输入二进制反汇编重建。

`evidence/` 保存原输入二进制摘要、原 1.2.0 反汇编、Beta8 ABI 与函数反汇编。`split-old/` 和 `world-old/` 是只读分析副本；它们不是新目标的编译输入。CI/发布只应采用本节列出的成品源码。

静态检查可以确认作用范围和调用条件，无法独立证明真机显示、触摸、动画和旋转锁定全部正常。本轮没有连接或部署手机。
