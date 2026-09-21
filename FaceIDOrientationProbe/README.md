# FaceIDOrientationProbe 0.1.0

这是一个与 MangoUpsideDownWorld 完全分离的只读诊断插件，目标环境为：

- iPhone 13 mini
- iOS 16.5
- Dopamine RootHide
- arm64e

## 它会做什么

插件只注入 `biometrickitd` 和 `coreauthd`。它不会 Hook 方法，不修改 Face ID、密码或 ACM
认证结果，也不会传入伪造方向。

它每 5 秒检查一次 dyld 映像数量。映像数量发生变化时，会记录：

- BiometricKit、BKDM、LocalAuthentication、CoreAuthentication 等相关映像的真实路径和 UUID；
- 相关映像中的 Objective-C 类；
- 名称包含 orientation、pose、camera、Pearl、biometric、match 等关键词的真实方法及类型编码。

日志优先写入：

`/var/mobile/Library/Logs/FaceIDOrientationProbe/Probe.log`

如果守护进程无法访问该目录，则回退到：

`/var/tmp/FaceIDOrientationProbe.log`

## 安装与测试

1. 使用 Sileo 或 Filza 安装 RootHide arm64e `.deb`。
2. 执行一次“重启用户空间”，让 `biometrickitd` 和 `coreauthd` 重新启动并加载 Probe。
3. 正常竖屏点亮锁屏，完成两次 Face ID 尝试。
4. 左横屏和右横屏各完成两次 Face ID 尝试。
5. 倒置竖屏完成三次 Face ID 尝试，其中至少一次保持倒置 10 秒以上。
6. 等待 10 秒后，用 Filza 导出上述日志文件。

## 风险与恢复

虽然本插件不安装任何 Hook，但它注入了生物识别相关守护进程，仍属于敏感测试组件。
如果 Face ID 服务反复重启、设置中 Face ID 暂时不可用或系统异常：

1. 进入 Dopamine 安全模式或关闭越狱注入；
2. 在 Sileo 中卸载 `FaceIDOrientationProbe`；
3. 再次重启用户空间；
4. 必要时完整重启设备后重新越狱。

不要与后续可能修改认证参数的实验包混装。本版本只是定位模块，不是修复包。

## 已有静态证据

已分析的 iOS 16.5 `ModuleACM` 是 arm64e CoreAuthentication bundle。它负责 ACM 策略验证、
认证机制调度和 RemoteUI。文件中没有找到 PortraitUpsideDown、设备方向、相机姿态或人脸图像
旋转逻辑。唯一方向相关开关是 `allowLandscapeTouchID`，它属于 Touch ID 横屏 UI 实验路径，
不是 Face ID 倒置识别入口。
