# MangoIdleIsland 0.1.0（实验版）

适用：iPhone 13 mini，iOS 16.5，Dopamine RootHide，Mango 1.0-Beta7-1；已启用系统灵动岛模拟和 Mango 液态玻璃。仅注入 SpringBoard。独立于 MangoUpsideDownWorld、FaceID 和原来的 Probe。

## 本版效果与边界

空闲时，在原有灵动岛容器里补一个系统磨砂材质胶囊。活动时撤掉补充背景，让 Mango 原来的内容正常显示。本版空闲背景不是 Mango 的液态玻璃着色器，不能保证外观一致。

补充视图不接收触摸，不挂手势识别器，不改变原有视图的 hidden、alpha、transform 或触摸区域。用户报告的“消失后长按仍有震动”说明至少有相关手势路径存在；尚未证明该手势具体属于哪个视图，本版不对它动手。

保守限制：只接受日志出现过的交互型 SBSystemApertureWindow、可见容器、隐藏且没有子视图的内容层、110–140 × 28–45 点容器。其他尺寸和不确定状态都退出，因此不同模拟机型或横屏不保证显示。已有的倒置/缩放从父视图继承。

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
3. 完全结束活动（仅暂停可能仍保留活动）：胶囊应回到空闲显示。
4. 倒置后重复上面三项，检查位置与原有长按/通知交互。
5. 息屏、亮屏、锁屏、横屏：不得出现遮挡、残留背景或新增触摸异常。横屏不强制显示。

状态日志：`/var/mobile/Library/Logs/MangoIdleIsland/Status.log`，只在状态变化时写入，约 64 KiB 循环截断，不记录通知文字。`state=idle background=1` 表示补充背景已挂载；其他 state 表示保守退出。每次 Respring 有新的 SESSION。

## 实现与性能

仅 Hook 经运行时检查的 SBSystemApertureContainerView.layoutSubviews（返回 void，无额外参数），原方法先执行。500ms 的主线程兜底扫描仅搜索灵动岛窗口（最多 256 个节点），避免活动边界遗漏；切换最多可能延后约半秒。仅布局调用可能无法覆盖所有内容生命周期，所以保留此扫描，不能宣称零开销或完全无闪烁。

不注入 backboardd；不修改 Mango 文件、授权逻辑、偏好或系统方向。不使用固定函数地址。仅支持 iOS 16.5.0，其余系统自动退出。无法识别类或签名时不安装 Hook。

## 编译

RootHide Theos + iPhoneOS16.5 SDK + Apple Clang，`make package FINALPACKAGE=1`。ARCHS=arm64e，THEOS_PACKAGE_SCHEME=roothide；不要用普通 rootless 的 arm64 包冒充 RootHide 构建。GitHub 工作流执行编译、包结构及 Mach-O 架构检查。

这是首个实机待验证修复包。编译和静态验证通过不等于已证明所有系统场景正确。
