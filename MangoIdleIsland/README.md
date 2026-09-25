# MangoIdleIsland 1.0.0

1.0.0 重写了「设置 → 灵动岛玻璃调整」中的色调强度实现。此前 0.5.1 虽然把该滑块命名为 `Island.TintStrength`，实际保存时却把滑块值转换为颜色字符串末尾的 alpha，并改写 `Island.LightTintColor` / `Island.DarkTintColor`。静态核查 Mango 1.0-Beta7-1 的渲染模块后确认，Mango 存在独立的 `.TintStrength` 参数，因此旧映射不正确。

从 1.0.0 开始，色调强度直接一对一读写 `Island.TintStrength`，不再修改浅色/深色色值或颜色透明度。设置修改后仍写入 `com.go.mangoosprefs` 并发布 `go.mangoos/ParametersReloaded`，由现有参数刷新路径重新应用 Island 玻璃参数。CI 额外检查 PreferenceBundle 必须包含 `Island.TintStrength`，并禁止旧的 `Island.LightTintColor` / `Island.DarkTintColor` 映射重新进入构建产物。

本版同时保留 0.5.1 已补齐的逐项设置说明。色调通透、色调强度、边缘光、边缘光调整、光斑和全局光斑强度均显示对应作用范围。

适用：iPhone 13 mini，iOS 16.5，Dopamine RootHide，Mango 1.0-Beta7-1；已启用系统灵动岛模拟和 Mango 液态玻璃。仅注入 SpringBoard。独立于 MangoUpsideDownWorld、FaceID 和原来的 Probe。

## 参数映射

- 色调通透 → `Island.Blur`，范围 0–3，未写入时界面按约 1.7 显示。
- 色调强度 → `Island.TintStrength`，范围 0–1，未写入时界面按约 0.10 显示。
- 边缘光 → `Island.SpecularEnabled`。
- 边缘光调整 → `Island.SpecularOpacity`，范围 0–1。
- 光斑 → `Island.DispersionEnabled`。
- 光斑强度（全局）→ `Global.DispersionStrength`，范围 0–20；该值不是 Island 独占参数，也会影响其他启用光斑的 Mango 玻璃。

仅当明确开启 Island 边缘光时，解除 Mango 原始活动玻璃及本插件空闲玻璃针对 Island 的边缘光禁用覆盖；关闭时保留原行为。旧版动画、位置和触摸逻辑不变。

## 本版效果与边界

空闲时，在原有灵动岛容器里添加补充背景。若 Mango 液态玻璃已启用，或已经观察到活动时的原版玻璃，则使用 Mango 的 `MGLiveBackdropView`，`groupName=Island`、`filterType=go.mangoos.island`。若尚未确认其可用，暂时使用系统磨砂；观察到原版玻璃后可自动升级。

活动动画期间补充背景留在 Mango 内容下层，跟随容器几何尺寸、按当前活动玻璃层的显示透明度交接；活动内容首次达到完全可见后留约 60ms 重叠窗口，减少合成器第一帧空白。收缩中即使内容层尚未变为 hidden，补充背景也会按活动玻璃层的实际可见度恢复。没有活动玻璃层时才参考 SAUIElementView 的可见度。

补充视图不接收触摸，不挂手势识别器，不改变原有视图的 hidden、alpha、transform 或触摸区域。

保守限制：只接受交互型 `SBSystemApertureWindow` 的可见容器，尺寸在 100–350 × 28–145 点；超出时隐藏补充背景。已有的倒置/缩放从父视图继承。

## 安装前先准备恢复

1. 保留现有 Mango 和倒置补丁；不要覆盖它们的 dylib。
2. 确认知道如何在 Dopamine 关闭 tweak 注入后重新越狱，并能在关闭注入后打开 Sileo/Filza。
3. 若安装后 SpringBoard 循环崩溃或黑屏：重启手机，在 Dopamine 关闭 tweak 注入后重新越狱，再用 Sileo 卸载 **MangoIdleIsland**（包名 `com.chenxun.mangoidleisland`）。卸载后才恢复注入。不要删除 Mango 原文件。
4. 仅需停止显示且 Filza 可用时：在 `/var/mobile/Library/Logs/MangoIdleIsland/` 新建名为 `DISABLED` 的空文件，约一秒内隐藏补充背景；此文件不能阻止启动阶段发生的崩溃，出现崩溃优先按第 3 项恢复。删除该文件可恢复显示。
5. RootHide 的注入目录会受其环境映射影响，不提供猜测的固定隐藏根路径。手动删除时只删除本包的 MangoIdleIsland.dylib 与 MangoIdleIsland.plist，优先使用 Sileo 卸载。

## 安装与实机检查

使用 Filza/Sileo 安装 **iphoneos-arm64e / RootHide** deb，Respring，等待约 12 秒。不需要再次转换此包。

依次检查：

1. 正常竖屏、没有活动：胶囊应显示；原位置长按震动应保持。
2. 播放音乐：原 Mango 灵动岛应显示，长按展开、进度条/音量拖动正常，不应有额外小胶囊遮挡。
3. 完全结束活动：观察从放大到缩小直至空闲的一整段动画，背景应连续、外观应与 Mango 活动玻璃相近。
4. 调整「色调强度」到明显不同的数值，确认空闲 Island 视觉发生变化；再触发活动 Island，确认参数重载没有破坏原有交互。
5. 倒置后重复上述检查，确认位置、长按、通知交互及玻璃视觉正常。
6. 息屏、亮屏、锁屏、横屏：不得出现遮挡、残留背景或新增触摸异常。横屏不强制显示。

状态日志：`/var/mobile/Library/Logs/MangoIdleIsland/Status.log`。`[GLASS] constructor-verified=1 reason=none module=.../mango.dylib` 表示运行时类及签名通过；`[GLASS] original-island-glass-observed` 表示在活动岛内发现原有玻璃；`[BACKGROUND] kind=Mango-glass` 才说明本插件确实创建了 Mango 玻璃。每次 Respring 有新的 SESSION。

## 实现与性能

Hook 运行时检查过的 `SBSystemApertureContainerView.layoutSubviews`、内容视图的 `setHidden:`、`SAUIElementView.didMoveToSuperview` / `setAlpha:` 以及 `MGLiveBackdropView.setHidden:`，原方法先执行，所有 hook 不修改参数或返回值。变化后会在约一秒内启动 30fps 局部过渡刷新，随后暂停；500ms 的低频兜底扫描只搜索交互型灵动岛窗口（最多 256 个节点）。补充背景位于活动内容下方，不接收触摸。

不注入 backboardd；不修改 Mango 原始文件、授权逻辑或系统方向。仅设置页面主动改动原版玻璃偏好。不使用固定函数地址。仅支持 iOS 16.5.0，其余系统自动退出。无法识别关键类或 hook 方法签名时不安装 Hook。安装 1.0.0 将升级此前 0.5.x；不需叠装。卸载插件不会自动移除已经写入 `com.go.mangoosprefs` 的 Island 偏好值。

## 编译

RootHide Theos + iPhoneOS16.5 SDK + Apple Clang，`make package FINALPACKAGE=1`。`ARCHS=arm64e`，`THEOS_PACKAGE_SCHEME=roothide`；不要用普通 rootless 的 arm64 包冒充 RootHide 构建。GitHub 工作流执行编译、包结构、PreferenceBundle 参数映射及 Mach-O 架构检查。

1.0.0 的核心修复是将色调强度恢复为 Mango 原生的一对一 `Island.TintStrength` 参数语义；编译和静态验证通过后仍需真机确认视觉幅度与 Mango 原版一致。
