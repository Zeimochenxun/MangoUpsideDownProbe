# FaceIDOrientationProbe 0.2.0

独立的观察型探针，不合并进 MangoUpsideDownWorld，不修复或绕过 Face ID。
仅适配本次设备：iPhone 13 mini（iPhone14,4）、iOS 16.5（20F66）、Dopamine RootHide。
源码编译和包检查不能代替真机测试。认证进程注入即使只读也有崩溃风险。

## 安装前先准备恢复

1. 记住设备密码，先确认正常竖屏 Face ID 可用。重启后的第一次解锁需要密码，不计入测试失败。
2. 确认可以在 Dopamine 中关闭插件注入后重新越狱。准备好系统强制重启操作：快速按音量加、快速按音量减、持续按侧边键直到 Apple 标志。重启后先不要开启插件注入。
3. 如果安装后认证异常但仍能操作，用密码解锁，卸载包 `com.chenxun.faceidorientationprobe`，再通过 Dopamine 重启用户空间。不要删除 Apple 框架或 Mango 文件。
4. 如果无法操作，强制重启后先用密码解锁，在关闭插件注入的状态下重新越狱，再从包管理器卸载这个独立包。不要假定 SpringBoard 安全模式一定阻止 biometrickitd 注入。
5. 本包不附带重启、杀进程或修改系统文件的安装脚本。

## 安装与启用

通过 RootHide 环境中的包管理器安装本项目 0.2.0 的 `iphoneos-arm64e` deb，覆盖同包名 0.1.0；不需要再次转换。
安装后使用 Dopamine 的“重启用户空间”。仅 Respring 不保证 biometrickitd 重启。
密码解锁一次，等至少 15 秒。不要同时更新 Mango、UpsideDowned 或现有视觉补丁。

在 Filza 打开新目录：

`/var/mobile/Library/Logs/FaceIDOrientationProbe-v02/`

这里应有 `Probe.log`、`Phase.txt`、`Disable.txt`。上一版的旧目录不会被删除或覆盖。
若目录不存在或只有 SKIP，没有 HOOK，停止测试并反馈；不要手动把系统目录权限改为 777。
成功挂接会出现 `[HOOK]`；`[COUNTS] hooks=1111` 表示四个接口均挂接。计数为零只代表尚未观察到调用，不证明系统没有方向信息。

## 手机端四方向测试

用 Filza 文本编辑器修改已有 `Phase.txt` 的内容，整份文件只保留下面一个标签；保留原文件所有者和权限。
保存后至少等待 2 秒，先把设备转到指定姿势，再开始尝试。刚保存到转动完成这一小段不用于判断。
标签是人工备注，不是 UIWindowScene 或传感器实测值。

| 标签 | 测试姿势（面向屏幕） |
| --- | --- |
| `portrait` | 刘海在上 |
| `upsideDown` | 刘海在下 |
| `landscapeLeft` | 本探针人工约定：刘海在左 |
| `landscapeRight` | 本探针人工约定：刘海在右 |

横屏标签不代表 UIKit 或 UIDevice 的同名枚举，不能直接套 1/2/3/4。
每个姿势：锁屏、唤醒、进行一次正常 Face ID 解锁，记录“成功 / 失败 / 未尝试（系统要求密码）”。
失败后用密码恢复，不要连续反复刷脸；四个姿势完成后，再做一次 portrait 对照。
保持距离、遮挡条件尽量一致，不在测试中重新录入面容、修改注视设置或关闭安全机制。

日志不会记录认证成功与否，结果需要人工说明。若系统要求密码、注视/遮挡条件改变，应明确标出，不推断为方向失败。

完成后把 `Disable.txt` 内容改为 `1`，等 2 秒，然后把 `Probe.log` 发回；如中途重启过用户空间，也提供 `Previous.log`。
一并写出四个方向各自结果和是否发生界面回正。

## 暂停、会话与日志限额

`Disable.txt` 为 `1` 或读取失败时停止记录和后续挂接。已挂接方法继续原样转发，不是运行时卸载。
重新启用须将文件改回 `0` 并重启用户空间。彻底移除须卸载包再重启用户空间。
每次 biometrickitd 启动新 Session，保留当前 Probe.log 和一份 Previous.log，每份最大 2 MiB。
达到上限停止记录，文件末尾不保证有终止标记。每个方法每秒最多保留 4 条样本，64 条内存队列；限流数和竞争丢弃数出现在 COUNTS。
文件为 0640、目录为 0750，控制文件为 0660，组使用本机 mobile 用户主组；只操作本探针专属目录。
无路径回退或权限绕过，日志目录无法安全打开则不安装 hook。
控制文件被编辑器替换成不同所有者时会被拒绝；Disable.txt 无法安全读取时自动暂停。

## 证据与 Hook 范围

以下签名来自提供的 0.1.0 实机元数据日志（PID 9399），不是虚构 API。

| 实例方法 | Objective-C 编码 | 观察内容 |
| --- | --- | --- |
| BiometricKitXPCServerPearl deviceOrientation | Q16@0:8 | 原始返回的无符号 64 位数 |
| BKFaceDetectStateInfo setOrientation: | v24@0:8Q16 | 原始无符号 64 位入参 |
| BKFaceDetectStateInfo orientation | Q16@0:8 | 原始返回的无符号 64 位数 |
| PearlCoreAnalytics sendMatchEventAnalytics:orientation:identities: | v40@0:8@16Q24@32 | 仅 orientation 标量入参 |

libBKDM2 UUID: `503938ad-b29d-3894-b44c-c2be6ffcef56`

BiometricKit UUID: `e9844b6f-4721-3d52-8988-68e1381b86f6`

在 hook 前检查进程、设备、系统 build、类自有方法、完整签名、当前 IMP 所属路径及 Mach-O UUID；不匹配就不挂接。不主动调用这些方法，不加载私有框架，不创建认证请求。
所有原始调用恰好转发一次，不改变实参/返回值；不记录人脸、身份对象、认证事件内容、密码、令牌或回执。
热路径仅尝试获取诊断锁、复制标量，锁被占用则丢弃记录，无磁盘写入和异步任务堆积。
此检查不能排除其他插件之后修改相同方法，也不是认证链安全性证明。

## 如何解释结果

- raw 数值变化只能说明这个具体接口收到或返回了不同值，不能先验认作 UIInterfaceOrientation。
- 各接口属于不同对象，未记录对象身份；相近时间不证明同一次认证中的直接传递关系。
- PearlCoreAnalytics 是统计线索，不据此认定可通过它控制 Face ID。
- 无调用或 SKIP 不等于不支持倒置。四方向值一样也需排除取样时机、缓存及其他方向入口。
- 本轮只据此选择下一轮逆向对象，不直接把 2 改成 1，也不修改 Secure Enclave、匹配阈值或认证结果。

## 构建

RootHide Theos + iPhoneOS16.5.sdk，`ARCHS=arm64e`，`THEOS_PACKAGE_SCHEME=roothide`。
源码 ZIP 根目录可执行 `make package FINALPACKAGE=1`。GitHub 仓库中的项目位于独立子目录 `FaceIDOrientationProbe`，专用 workflow 在仓库 `.github/workflows/faceid-orientation-probe.yml`。
CI 校验包只含本探针 dylib/plist、只注入 biometrickitd、arm64e 与版本正确；不改主项目。
