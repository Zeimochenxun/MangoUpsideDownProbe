# MangoIdleIsland 0.4.0（实验版）

适用：iPhone 13 mini，iOS 16.5，Dopamine RootHide，Mango 1.0-Beta7-1；已启用系统灵动岛模拟和 Mango 液态玻璃。仅注入 SpringBoard。独立于 MangoUpsideDownWorld、FaceID 和原来的 Probe。

## 本版效果与边界

空闲时，在原有灵动岛容器里添加补充背景。运行时类与构造签名经验证，并且 Mango 液态玻璃设置显示为开启，或在灵动岛活动中观察到 Mango 原始玻璃视图时，补充背景使用 Mango 自己的 `MGLiveBackdropView`，`groupName=Island`、`filterType=go.mangoos.island`。Mango 的配置优先从 RootHide 映射路径读取，再回退系统路径。若开机后还没有观察到活动玻璃，且设置读取不到，则暂时使用系统磨砂；首次看到原有 Mango 玻璃后自动升级材质，无需 Respring。原版 0.2.0 即使后来检测到玻璃也不会升级。0.3.0 又错误地只接受由 mangoos.dylib 提供的运行时类；用户提供的 `Status.log` 证实实际类来自 mango.dylib，因此 0.3.0 一直显示 `constructor-verified=0`。0.4.0 根据两份实际 Beta7-1 二进制的签名，接受上述两种来源。本插件只读取设置，不修改原设置或授权流程。

活动动画期间补充背景留在 Mango 内容下层，跟随容器几何尺寸、按当前活动玻璃层的显示透明度交接；活动内容首次达到完全可见后留约 60ms 重叠窗口，减少合成器第一帧空白。收缩中即使内容层尚未变为 hidden，补充背景也会按活动玻璃层的实际可见度恢复。没有活动玻璃层时才参考 SAUIElementView 的可见度。由于这里没有原生 iOS 设备运行时跟踪结果，不能承诺每种系统动画完全没有一帧闪烁。

补充视图不接收触摸，不挂手势识别器，不改变原有视图的 hidden、alpha、transform 或触摸区域。用户报告的“消失后长按仍有震动”说明至少有相关手势路径存在；尚未证明该手势具体属于哪个视图，本版不对它动手。

保守限制：只接受交互型 `SBSystemApertureWindow` 的可见容器，尺寸在 100–350 × 28–145 点；超出时隐藏补充背景。此范围涵盖用户日志中的收起、展开与过渡状态，避免旧版只在最终空闲态才显示导致的空白期。已有的倒置/缩放从父视图继承。

观察来源：用户 Probe.log 开始时，容器约 125 × 36.67 点、visible；内容层 hidden=1、childCount=0。活动开始后，内容层与 SAUIElementView/MGLiveBackdropView 出现。采样结束时仍有活动，没有观察到活动结束后再次空闲。

## 安装前先准备恢复

1. 保留现有 Mango 和倒置补丁；不要覆盖它们的 dylib。
2. 确认知道如何在 Dopamine 关闭 tweak 注入后重新越狱，并能在关闭注入后打开 Sileo/Filza。
3. 若安装后 SpringBoard 循环崩溃或黑屏：重启手机，在 Dopamine 关闭 tweak 注入后重新越狱，再用 Sileo 卸载 **MangoIdleIsland**（包名 com.chenxun.mangoidleisland）。卸载后才恢复注入。不要删除 Mango 原文件。
4. 仅需停止显示且 Filza 可用时：在 `/var/mobile/Library/Logs/MangoIdleIsland/` 新建名为 `DISABLED` 的空文件，约一秒内隐藏补充背景；此文件不能阻止启动阶段发生的崩溃，出现崩溃优先按第 3 项恢复。删除该文件可恢复显示。
5. RootHide 的注入目录会受其环境映射影响，不提供猜测的固定隐藏根路径。手动删除时只删除本包的 MangoIdleIsland.dylib 与 MangoIdleIsland.plist，优先使用 Sileo 卸载。

## 安装与实机检查

使用 Filza/Sileo 安装附带的 **iphoneos-arm64e / RootHide** deb，Respring，等待约 12 秒。不需要再次转换此包。

依次检查：

1. 正常竖屏、没有活动：胶囊应显示；原位置长按震动应保持。
2. 播放音乐：原 Mango 灵动岛应显示，长按展开、进度条/音量拖动正常，不应有额外小胶囊遮挡。
3. 完全结束活动（仅暂停可能仍保留活动）：特别观察从放大到缩小直至空闲的一整段动画，背景应连续、外观应与 Mango 活动玻璃相近。
4. 倒置后重复上面三项，检查位置与原有长按/通知交互。
5. 息屏、亮屏、锁屏、横屏：不得出现遮挡、残留背景或新增触摸异常。横屏不强制显示。

状态日志：`/var/mobile/Library/Logs/MangoIdleIsland/Status.log`，只在状态变化时写入，约 64 KiB 循环截断，不记录通知文字。`[GLASS] constructor-verified=1 reason=none module=.../mango.dylib` 表示运行时类及签名通过；`[GLASS] original-island-glass-observed` 表示在活动岛内发现原有玻璃；`[BACKGROUND] kind=Mango-glass` 才说明本插件确实创建了 Mango 玻璃。如果仍为 `kind=UIKit-fallback`，从 `reason` 判断是否签名检查失败。`state=background` 为无可见活动内容；`state=activity` 是过渡/活动期间的连续交接。每次 Respring 有新的 SESSION。

## 实现与性能

Hook 运行时检查过的 `SBSystemApertureContainerView.layoutSubviews`、内容视图的 `setHidden:`、`SAUIElementView.didMoveToSuperview` / `setAlpha:` 以及 `MGLiveBackdropView.setHidden:`，原方法先执行，所有 hook 不修改参数或返回值。变化后会在约一秒内启动 30fps 局部过渡刷新，随后暂停；500ms 的低频兜底扫描只搜索交互型灵动岛窗口（最多 256 个节点）。补充背景位于活动内容下方，不接收触摸。未运行视觉自动化或功耗实测。

不注入 backboardd；不修改 Mango 文件、授权逻辑、偏好或系统方向。不使用固定函数地址。仅支持 iOS 16.5.0，其余系统自动退出。无法识别关键类或 hook 方法签名时不安装 Hook。安装 0.4.0 将升级本包 0.3.0；不需叠装。

## 编译

RootHide Theos + iPhoneOS16.5 SDK + Apple Clang，`make package FINALPACKAGE=1`。ARCHS=arm64e，THEOS_PACKAGE_SCHEME=roothide；不要用普通 rootless 的 arm64 包冒充 RootHide 构建。GitHub 工作流执行编译、包结构及 Mach-O 架构检查。

这是首个实机待验证修复包。编译和静态验证通过不等于已证明所有系统场景正确。
