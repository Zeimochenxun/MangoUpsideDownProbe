# MangoOrientationProbe 0.3.0

## Mango 1.0-Beta7-1 分屏几何诊断
This branch is a **read-only diagnostic build**, scoped to the attached
`com.go.mango_1.0-Beta7-1_iphoneos-arm64e` binary (Mach-O UUID
`699ea8ae-c032-386e-b62d-f92fbff2a889`, SHA-256
`4603e13eaa5b535804ac3f1bc8d82452bb959d214d0fcaa944cef59bc9756369`).
It does **not** reverse the split interface yet. The earlier 0.2.0 binary
identity check would reject this Mango build, and applying a blind 180°
transform to all SpringBoard windows could invert touch and other overlays.

The new `[SPLIT-VIEW]` records describe actual `DecoratedFloatingView`
(launcher) and `DecoratedAppSceneView` (split scene) geometry in the screen's
fixed coordinate space. They include the center and two basis vectors, plus
the view's window and ancestry. `[SPLIT-SUMMARY]` reports whether those
views were present. The launcher pan hooks take snapshots at gesture end
and 400 ms later; the orientation notification does the same. All hooks
continue to pass the original arguments and return values through unchanged.

On the iPhone, capture a normal portrait baseline, an upside-down portrait
with the split launcher and an active split scene, and both landscape
orientations. Perform a split activation on each side in each orientation.
Export `/var/mobile/Library/Logs/MangoUpsideDownWorld/Probe.log` after the
session. The `[SPLIT-ACTIVATION]`, `[SPLIT-VIEW]`, `[SPLIT-SUMMARY]` and
`[ROOT-WINDOW-GESTURE]` lines identify which coordinate layer needs a
correction. A successful package build alone cannot verify visual or touch
alignment on the device.

## 旧版探针说明


这是面向 iOS 16.5、Dopamine RootHide、SpringBoard 的**只读定向 Probe**。它不修改 Mango 的方向值、布局、手势、触摸或视图变换。除记录实际 `mango.dylib` 已确认存在的入口外，0.2.0 还把 `UIRootSceneWindow` 与 `FBRootWindow` 纳入运行时只读分析。

日志固定写入：

`/var/mobile/Library/Logs/MangoUpsideDownWorld/Probe.log`

每次 SpringBoard 启动都会追加一个新的 `[SESSION]`。超过 4 MiB 时，旧日志会轮转到 `Probe.previous.log`。

## 安装前

保留：

- Mango 原版
- UpsideDowned
- 当前能让灵动岛视觉正常的 MangoUpsideDownWorld

建议暂时卸载旧的宽泛调试包 `MangoUpsideDownProbe`，以免日志和 Hook 链混在一起。本包 ID 是 `com.chenxun.mangoorientationprobe`，不会覆盖 Mango 或 MangoUpsideDownWorld。

## 四方向测试

每个方向都执行一次相同流程：

1. 切换到目标方向并等待 2 秒。
2. 让一条 Mango 通知灵动岛出现。
3. 做一次“视觉向上”的清除手势。
4. 再触发通知，做一次“视觉向下”的进入 App 手势。
5. 在横屏下额外尝试一次分屏启动热区；成功与失败各尝试一次。

顺序建议：Portrait(1) → PortraitUpsideDown(2) → LandscapeLeft(3) → LandscapeRight(4)。

测试后用 Filza 打开上述日志路径，把 `Probe.log` 整个发回。无需 Xcode、电脑、`log stream` 或 `grep`。

## 预期日志

```text
[ORIENTATION] ... system=2 ... mango=2 ... mode=2 ...
[MANGO-GESTURE] ... path=SBSystemApertureViewController._handleResizePan ... orientation=2 branch=portraitFallback ...
[MANGO-GESTURE] ... path=MangoPillElement.handlePanGesture ... translationY=... predicted=dismissWithContent ...
[MANGO-ACTION] ... selector=dismissWithContent: ...
[SPLIT-ACTIVATION] ... selector=launcherPanned: ... locationX=... locationY=...
[ROOT-WINDOW-CLASS] class=UIRootSceneWindow exists=1 ...
[ROOT-WINDOW-CLASS] class=FBRootWindow exists=1 ...
[ROOT-WINDOW] ... sceneOrientation=2 frame=... bounds=... transform=... fixedOrigin=...
[ROOT-WINDOW-GESTURE] ... windowClass=... originInWindow=... chain=...
```

`visual=manual` 是有意设计：代码不能可靠判断人眼看到的最终朝向，因此不伪造“视觉正确/错误”。手势输入、Mango 实际动作与方向值会被自动记录，结合四方向测试即可判断语义是否反转。

### UIRootSceneWindow / FBRootWindow 监控内容

- 类是否真实存在、所属系统镜像、父类链、是否为 `UIWindow` 子类。
- 类自身声明的、名称涉及 orientation/rotation/scene/window/frame/bounds/transform/coordinate/layout/hitTest 的真实方法及类型编码。
- 相关 ivar 的真实名称、类型和偏移。
- 实例的 frame、bounds、center、transform、windowLevel、key/hidden 状态。
- `UIWindowScene.interfaceOrientation`。
- `UIScreen.coordinateSpace` 与 `fixedCoordinateSpace` 中窗口原点、右下角的映射。
- Mango 手势 view 所属 window、view→window 坐标和父视图链。

Probe 不会 Hook 这两个类的未知私有 selector；先从日志确认真实结构后再决定是否需要更窄的 Hook。

## 安全与恢复

本包只观察并调用原实现，但仍然注入 SpringBoard。安装前确保 Filza 或 SSH 可用。

若发生 SpringBoard 循环崩溃：

1. 进入 Dopamine/RootHide 的禁用 tweak 或安全模式。
2. 用包管理器卸载 `com.chenxun.mangoorientationprobe`。
3. 或通过 SSH 执行 `dpkg -r com.chenxun.mangoorientationprobe`，然后 `sbreload`。
4. 不要删除或替换 Mango 原始 dylib。

本 Probe 检查目标 Mango Mach-O UUID，只有 UUID 为 `67c0d7c2-4487-3fd2-9535-067745ae4b8f` 且方法类型编码完全匹配时才安装 Mango Hook；否则只记录 `[PROBE-ABORT]` / `[HOOK-REFUSED]`。

## 当前边界

- 不修复行为。
- 不全局 Hook `UITouch`、`hitTest:`、`translationInView:` 或 `velocityInView:`。
- 不修改 framebuffer、BackBoard 或系统方向。
- 不分析授权、许可证、收据或付费验证。

静态结论和地址见 `STATIC_FINDINGS_ZH.md`。
