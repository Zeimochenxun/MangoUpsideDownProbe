# MangoSplitUpsideDownFix 0.1.1-alpha2

这是基于 `Probe 2.log` 的首个设备测试版，面向 iOS 16.5、Dopamine RootHide、Mango 1.0-Beta7-1。

0.1.1 修复了与只读探针并存时的身份识别失败：验证定义 Mango 视图类的原始镜像及 UUID，不再误将探针包装后的方法入口视为 Mango 自身。0.1.0 因此会在日志里写入 `[FIX-ABORT]`，没有执行任何旋转。

日志确认倒竖屏（orientation=2）时，`DecoratedFloatingView` 与 `DecoratedAppSceneView` 仍使用正竖屏的 frame、center 和正向坐标基。此版本只寻找实际包含这些 Mango 分屏视图的独立全屏 `UIWindow`，在倒竖屏时对整个窗口施加 180° 变换；回到其他方向时恢复。这样保留 Mango 在子视图上的 0.8/0.85 缩放动画，并让渲染、触摸测试和手势坐标一起旋转。

安全限制：

- 只注入 SpringBoard。
- 只接受日志和所给 deb 已确认的两个 Mango Beta7 Mach-O UUID。
- 只处理精确类名为 `UIWindow`、bounds 与固定屏幕大小一致、anchorPoint 为 `(0.5,0.5)`，且变换为 identity/180° 的窗口。
- 不 Hook 全局触摸、手势或 Mango 授权逻辑。
- 不与 MangoUpsideDownWorld 冲突，也不要求卸载它。

安装后执行 respring。建议卸载只读诊断包 `com.chenxun.mangosplitgeometryprobe`，但两者并存也不会改动同一状态。

如果出现异常，可先创建空文件：

`/var/mobile/Library/Preferences/MangoSplitUpsideDownFix.disabled`

修复会在 350 ms 内把已旋转窗口恢复为原状。随后卸载 `com.chenxun.mangosplitupsidedownfix` 并 respring。运行日志位于：

`/var/mobile/Library/Logs/MangoSplitUpsideDownFix/Fix.log`
