# UpsideDowned 源码与上传二进制核对

日期：2026-09-17。原文件只读，未修改，也未分析 Mango 授权机制。

## 结论

**已证实：这款插件是 SpringBoard 的方向策略解锁器。它允许系统进入倒置/横屏，但没有自行设置整屏输出矩阵或 HID 触摸变换。** 这不等于画面“假旋转”：系统会执行获准的方向切换，但不同场景和覆盖层是否跟随仍由各自逻辑决定。

用户转向独立系统旋转方案是合理的研究方向。不过，把该源码中的一个返回值改成 2、或再加一个 UIView 的 π 旋转，都不能由此保证整块显示输出和触摸统一反转。

## 输入与来源

- 上传 `upsidedowned.dylib`：151776 字节。
- SHA256：`8132800d6338a827fb72ff69d939f2a72d2576c1bcfd343fc524c47570f28996`。
- 上传 plist 是合法的 OpenStep 文本格式，不能直接交给只接受 XML/binary 格式的 Python plistlib 判断好坏。
- plist 的 Executables 是 `SpringBoard`，Bundles 是 `com.apple.springboard`。
- [开源仓库](https://github.com/34306/upsidedowned)，核对提交 `b542ebe44305d12e19126d7d5481e6f4ab05615a`，源码 `Tweak.xm` Git blob SHA `25397980ecf3f561ffe460059ea15070caca08e5`。
- 上游为 MIT 许可，声明来自 [TrollPad](https://github.com/khanhduytran0/TrollPad)。附带 UpsideDowned 的源码与其 LICENSE，不把整个 TrollPad 搬入新工程。

## Mach-O 情况

| 项目 | arm64 slice | arm64e slice |
|---|---:|---:|
| fat 文件偏移 | 0x4000 | 0x14000 |
| slice 长度 | 53264 | 69856 |
| CPU subtype 原始值 | 0x0 | 0x80000002 |
| function starts 数量 | 8 | 8 |
| 自定义 ObjC 类 / category | 0 / 0 | 0 / 0 |
| 注册 Hook 数 | 7 | 7 |

保留 Logos 的本地 C++ 修饰符号与源码构建路径，未完全 strip；这 8 个函数均可解析，没有在它们中发现加壳或控制流混淆迹象。arm64e 的 PAC 指令是指针认证，不是混淆。

依赖 libobjc、Foundation、CoreFoundation、`@loader_path/.jbroot/usr/lib/libsubstrate.dylib`、libc++、libSystem；`/Library/MobileSubstrate/DynamicLibraries/upsidedowned.dylib` 是 LC_ID_DYLIB 自身标识，不是外部依赖。实际导入主要是 `_MSHookMessageEx` 和 `_objc_getClass`，arm64 另有 `dyld_stub_binder`。

## 全部 Hook 的地址与职责

地址为各 slice 内未滑移 VM 地址，不能当作手机运行地址。初始化分别位于 `0x4000`，通过 MSHookMessageEx 安装替代函数。未定义同名 ObjC 类，因此表中的类是 Hook 目标，不是插件自己新增的类。

| Hook 目标 | arm64 | arm64e | 已核对行为 |
|---|---:|---:|---|
| UIDevice userInterfaceIdiom | 0x415c | 0x41b4 | forcePadIdiom > 0 时返回 1，否则调用原函数 |
| SBTraitsSceneParticipantDelegate _isAllowedToHavePortraitUpsideDown | 0x41c0 | 0x421c | 返回 YES |
| SBTraitsSceneParticipantDelegate _orientationMode | 0x41dc | 0x4238 | 临时增加 forcePadIdiom，调用原函数，再减少并返回原结果 |
| SpringBoard homeScreenRotationStyle | 0x4240 | 0x42a0 | 返回 1 |
| SBApplication isMedusaCapable | 0x4258 | 0x42b8 | 返回 YES |
| SBHomeScreenViewController supportedInterfaceOrientations | 0x4274 | 0x42d4 | 原返回值 OR 4 |
| SBCoverSheetPrimarySlidingViewController supportedInterfaceOrientations | 0x42ac | 0x4310 | 原返回值 OR 4 |

源码解释 `userInterfaceIdiom` 返回的 1 是 `UIUserInterfaceIdiomPad`。`forcePadIdiom` 是全局 uint16_t；arm64e 在 0xc068，`ldrh/strh` 读写。在 `_orientationMode` 的原调用期间，相关系统代码会临时收到 iPad idiom。这里没有把所有方向 getter 全局改成 portraitUpsideDown。

关键 arm64e 链：

1. `0x4238` `_orientationMode`：在 `0x4258–0x4260` 增加计数。
2. `0x4268` 加载原函数指针，在 `0x4274` 用 `blraaz x8` 调用。
3. 在 `0x4280–0x428c` 减少计数，返回原函数结果。
4. 在这段原调用期间，若系统读 `UIDevice userInterfaceIdiom`，`0x41b4` 会按计数分支决定返回 iPad idiom 或调用原实现。

方向掩码链：`0x42d4 → 0x42fc blraaz → 0x4300 orr x0,x0,#4`，锁屏对应 `0x4310 → 0x4338 blraaz → 0x433c orr x0,x0,#4`。**4 是方向掩码的一个 bit，不是方向枚举值，也不是旋转角度。** 这两个函数没有布局浮点参数、CGRect 运算或触摸坐标参数。

8 个函数中没有设置 frame/center/transform、创建 island view、修改 shader 或通过 IPC 请求 display/HID 变换的自定义路径。经上述逐函数核对，可认为所上传版本的旋转逻辑与该公开源码一致；未声称源码能字节级重建同一个签名二进制。

## 对故障的解释范围

**证据支持：** 当前倒置插件只改变允许的方向和设备 trait 判断。它没有实现“最后把所有已合成像素再统一转 180°”的机制，所以不能据它的桌面效果保证灵动岛等覆盖层同步。

**仍需实测：** 方向切换后，iOS 是否也改了 CAWindowServerDisplay 的 orientation、岛所在窗口矩阵是否另有写入、以及触摸采用哪个空间。不能从本插件没有调用显示 setter，进一步断言整个系统完全没有调用它；原系统函数内部仍可能这样做。

## 真正整屏反转的技术路线

理想状态是在逻辑空间不改变布局的情况下，对最终显示应用 F，并让输入到逻辑空间使用 F 的逆变换。以原点 (0,0)、尺寸 W×H 的连续坐标空间为例，180° 变换为 `(x,y) → (W−x,H−y)`，逆变换相同。离散像素索引可能使用 W−1/H−1；设备点、像素、归一化 HID 坐标不能混用。

必须同时确定：

1. 内屏最终显示变换入口是否覆盖系统覆盖层；
2. 物理触摸与系统边缘手势是否同步映射；
3. 禁止现有逻辑旋转再叠加一次，明确启停和方向检测；
4. 恢复普通竖屏、横屏、锁屏/唤醒时如何恢复全部原状态。

目前较有依据的候选是 `CAWindowServerDisplay orientation/setOrientation:`：公开运行时头文件存在这些方法，iOS 16.5 SDK 导出 CAWindowServerDisplay 与 `kCAWindowServerOrientation_PortraitUpsideDown`。但这不是 iPhone 内屏可用性和触摸同步的证明。

`BKSHIDServicesSetDeviceInterfaceOrientation`、`BKSHIDServicesGetCALayerTransform`、`CARenderServerSetAXMatrix` 在 SDK 中存在。仅有符号不够确定 ABI 和含义，本轮不为它们编造函数指针或调用。普通截图也不一定显示最后扫描输出层的旋转，因此下一轮应配合实拍照片。

## 已交付的下一步

独立 `SystemFlipProbe` 只读诊断源码和 RootHide 构建工作流：SB 模块记录公开窗口/场景几何，BB 模块读取现有显示服务器状态和上下文点转换。共享自定义 Darwin 通知只用于触发采样，不属于 Mango 或 Apple 已有通知。

获取两份现场日志后，可以判断是否适合做带超时恢复的显示层试验。**当前没有实现或验证全局显示/HID 强制反转；诊断包不是该功能的完成品。**

详细恢复与采集步骤见根目录 README.md。证据目录包含各 slice 的 load commands、selector/symbol 表和全部 ARM64 反汇编；不包含付费 Mango 二进制。
