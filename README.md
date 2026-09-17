# MangoOrientationProbe 0.1.0

这是面向 iOS 16.5、Dopamine RootHide、SpringBoard 的**只读定向 Probe**。它不修改 Mango 的方向值、布局、手势、触摸或视图变换，只记录已经由实际 `mango.dylib` 确认存在的类和方法。

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
```

`visual=manual` 是有意设计：代码不能可靠判断人眼看到的最终朝向，因此不伪造“视觉正确/错误”。手势输入、Mango 实际动作与方向值会被自动记录，结合四方向测试即可判断语义是否反转。

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
