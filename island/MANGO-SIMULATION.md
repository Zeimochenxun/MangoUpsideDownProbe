# Mango「灵动岛模拟」各项功能的依据

2026-10-31。样本是 Mango Beta9 基线（`MangoHello.dylib` sha256 `3a8b0fc1af84139f5bc9b304eba65913fce40a1f01d8a6bbf653e09380568736`，`MangoPanda.dylib` `dc686c4ba186fcd9872740ad8340295275892ee82c2afbfdf03624101823466f`，设置页 `MangoOSPrefs` `c9977da48bdda0eb7f8307b31268f3e78be0a67a342036e036c2def3c4fdd3eb`）；Beta12 的 `MangoDynamicIslandSimulation` 方法集、路径、键、数值与它逐项相同（2026-10-22 的对比，见 `E:\mango-beta12-rea\REPORT.md`）。没有比 Beta12-1 更新的包。

方法：只读静态分析加自写的 AArch64 解释器。解释器按函数真实的控制流逐条执行（调用跳过，返回值可指定），记录写入内存的字符串和每次调用的参数。**没有在真机或模拟器上运行 Mango，没有执行 Mango 的原生代码。**

标签：**【读】** 解释器或反汇编直接给出；**【推】** 由读到的推出来；**【缺】** 没读到或没验证。

Mango 把运行时字符串加密存放，按字节异或还原；中文界面文字是运行时拼成的 UTF-16，所以 2026-10-22 那轮只扫 ASCII 的字符串转储里没有它们。这次用解释器直接取了写出来的 UTF-16。**许可/授权相关的字符串没有分析，也没有记录。**

## 1. 菜单里「灵动岛」一栏的结构

菜单文字及其先后顺序是【读】：`-[MangoMenuViewController viewDidLoad]`（0x329268）的解释器输出，按文字出现的地址排序（地址随代码顺序递增）。单独一条「灵动岛」文字后面依次是下表各项；「灵动岛」是这一栏的标题、以及每项文字对应哪个配置键，是按名字对应的【推】（`MangoConfig` 里确有这些键，`MangoMenuViewController` 里确有这些开关和滑块，文字没有和键直接连起来）。

| 菜单项 | 对应配置/控件【推】 | 属于 |
|---|---|---|
| 多岛共存 | `MangoPillMultiIslandEnabled` | 消息岛 |
| 前台退岛动画 | `MangoSwitcherIslandExitEnabled` | 消息岛 |
| 岛消失延迟 | `MangoPillDismissDelay`（滑块） | 消息岛 |
| 岛点击行为 | `MangoPillTapAction`（全屏打开 / 分屏打开 / 回复消息 / 退出消息岛 / 常驻消息岛） | 消息岛 |
| 岛下拉手势、岛上滑手势 | `MangoPillSwipeDownAction`、`MangoPillSwipeUpAction` | 消息岛 |
| 岛宽度压缩 | `MangoPillWidthOffset`（滑块） | 消息岛 |
| 模拟通知 | `simulatePillNotification`（测试按钮） | 消息岛 |
| **模拟灵动岛模式** | `MangoDynamicIslandSimulationMode`，按钮 | **灵动岛模拟** |
| **应用模拟灵动岛** | 按钮，`dynamicIslandSimApplyTapped` | **灵动岛模拟** |
| **预设** | 菜单，`buildResolutionPresetMenu` | **灵动岛模拟（分辨率）** |
| **应用分辨率** | 按钮，`resolutionApplyTapped` | **灵动岛模拟（分辨率）** |

再往后是 启用音量滑条 / 锁屏音量滑条 / 灵动岛音量滑条 / 灵动岛分屏快捷行 / 灵动岛自绘频谱 / 音频跳动 / 专辑图脉冲 / 专辑颜色自适应 / 频谱样式【读】；紧接着的说明文字是「模拟灵动岛适用于 16.1 及以上系统的无实体岛设备…」和「开启/关闭需重启用户空间生效」，看位置是这一栏的脚注【推】。玻璃、黑色光晕、位置与缩放在设置页（`MangoOSPrefs`）的「进阶液态 → 灵动岛功能」里【读：设置页的本地化文字文件】。

本插件对应的是加粗的四项，加上位置与缩放；其余见 README 的「灵动岛一栏里没有做的」。

## 2. `MangoDynamicIslandSimulation`：14 个类方法【读】

地址是 Beta9 `MangoHello` 里的函数地址。

| 方法 | 地址 | 读到的行为 |
|---|---|---|
| `readArtworkDeviceSubType` | 0xd04624 | 读 `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist` → `CacheExtra` → `oPeik/9e8lQWMszEjbPzng`（同时解出名字 `ArtworkDeviceSubType`）→ 整数 |
| `modifyArtworkDeviceSubType:` | 0xd06108 | 同一文件：读成可变字典，改这个键，`dataWithPropertyList:` 写回，原子替换，`@try/@catch` |
| `enableWithMode:` | 0xd03144 | 参数 0 → 调 `modifyArtworkDeviceSubType:0x9fc`（2556）；参数 1、2 → `0xaec`（2796）；随后 `performUserSpaceReboot` |
| `disable` | 0xd03c10 | 调 `defaultDeviceSubType`，把结果交给 `modifyArtworkDeviceSubType:`，随后 `performUserSpaceReboot` |
| `defaultDeviceSubType` | 0xd02e90 | 控制流打平的状态机，真正做的只有：`[UIScreen mainScreen]` → `nativeBounds` → `fcvtzs x8, d3`（d3 是 CGRect 的高）→ 返回。**没有机型表** |
| `currentArtworkDeviceSubType` | 0xd028cc | 调 `readArtworkDeviceSubType` 和 `nativeBounds`；读不到缓存值时回退到屏幕高度【推：回退条件没逐条还原】 |
| `isCurrentlyEnabled` | 0xd020cc | 调 `currentArtworkDeviceSubType` 和 `defaultDeviceSubType`。用解释器给这两个选择子指定返回值逐组合跑：(当前,默认)=(2340,2340)→0，(2340,2556)→0，(2556,2340)→1，(2556,2556)→0，(2796,2340)→1，(2796,2556)→1，(0,2340)→0，(0,2556)→0。即：当前值是 2556 或 2796，且不等于默认值 |
| `performUserSpaceReboot` | 0xd08378 | `CFNotificationCenterPostNotification(DarwinNotifyCenter, "com.go.mango.respring", NULL, NULL, YES)`；SpringBoard 里的观察者回调先检查 `getprogname()=="SpringBoard"`，再 `[[FBSystemService sharedInstance] exitAndRelaunch:YES]`（2026-10-22 读） |
| `resolutionPresets` | 0xd08e1c | 10 项，每项是 `{?=@qq}`：名字、宽、高（第 3 节） |
| `selectedResolutionPresetIndex` / `setSelectedResolutionPresetIndex:` | 0xd0a510 / 0xd0b368 | 存在 `NSUserDefaults` 的 `MangoResolutionPresetIndex` |
| `nativeResolution` | 0xd0c0a0 | 返回 `CGSize`（`nativeBounds` 的尺寸） |
| `applyResolutionWithWidth:height:` | 0xd0c254 | `fileURLWithPath:@"/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist"` → `removeItemAtURL:error:` → `numberWithInteger:` 两次 → `dictionaryWithObjects:forKeys:count:`（键 `canvas_height`、`canvas_width`）→ `writeToURL:atomically:`（YES）→ `fileURLWithPath:@"/private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist"` → `removeItemAtURL:error:` → `createSymbolicLinkAtURL:withDestinationURL:error:` → `dispatch_time(0, 0x1dcd6500 = 0.5 s)` → `dispatch_after` 里 `performUserSpaceReboot` |
| `restoreDefaultResolution` | 0xd10db0 | `removeItemAtPath:error:` 两个路径各一次 → `dispatch_time(0, 0.5 s)` → `dispatch_after` 里 `performUserSpaceReboot` |

【读】`modifyArtworkDeviceSubType:` 里各选择子的调用点各只有一处：`objectForKeyedSubscript:`（0xd0785c，取 `CacheExtra`）、`numberWithInteger:`（0xd07acc）、`setObject:forKeyedSubscript:`（0xd07b28，设机型键）、`dataWithPropertyList:format:options:error:`（0xd08144）、`writeToURL:atomically:`（0xd08288）。没有第二次读取、也没有 `isKindOfClass:`：Mango **不检查机型这一项原来在不在，直接设**，缓存里没有就是加上。`currentArtworkDeviceSubType` 读不到缓存值时回到屏幕高度，说明 Mango 自己就预期有的机器上这一项是缺的。0.2.0 把「这一项不在」当成错误（「读不到当前的机型值」），上机第一步就被它挡住；0.2.1 照 Mango 的做法加上，并把「原来没有」记下来，取消时删掉。

【缺】`currentArtworkDeviceSubType` 的回退细节；`defaultDeviceSubType` 取整用的是 `fcvtzs`（向零截断），本插件用四舍五入，面板像素高是整数时两者相同。

【推】Mango 的 `defaultDeviceSubType`、`isCurrentlyEnabled`、弹窗里的「当前原生」都实时读 `UIScreen.nativeBounds`。如果应用画布后 `nativeBounds` 报告的是画布尺寸（改画布的目的就是这个，但没在设备上见过），这几处在 Pro 尺寸的画布下会得出「这台机器本来就有灵动岛」、取消模拟时写回 2556。本插件不照搬这一点：没有画布时把面板尺寸记下来，画布生效期间用记下的值（README 里的「面板尺寸」）。

### 菜单端的流程【读】

- `updateDynamicIslandSimModeButtonTitle`（0x31f134）：模式 0 的标题 `Pro (1179×2556)`，其余 `Pro Max (1290×2796)`。模式菜单的两个动作（0x36f804、0x36fad0）分别 `setDynamicIslandSimulationMode:` 0 和 1，后者再调 `updateDynamicIslandSimModeButtonTitle`。
- `updateDynamicIslandSimApplyButtonTitle`（0x31fff0）：`isCurrentlyEnabled` 为真显示「取消模拟」，否则「应用」。
- `dynamicIslandSimApplyTapped`（0x320960）：先调一个桩函数 0xe5c5ec，参数是 (2, 16, 1, 0)，和编译器给 `@available(iOS 16.1, *)` 生成的 `__isPlatformVersionAtLeast(iOS, 16, 1, 0)` 的签名一致（这个二进制里没解析出该桩的名字【推】；解释器里让它返回 0 就走到下面的版本提示，返回 1 就往下走【读】），低于 16.1 弹「系统版本不支持」（正文「灵动岛模拟需要 iOS 16.1 及以上系统，当前系统版本过低，强行使用可能导致设备异常」）和「知道了」；否则看 `isCurrentlyEnabled`：为真弹「取消模拟灵动岛」（正文含 `defaultDeviceSubType` 的值，按钮「确定恢复」「取消」），为假弹「模拟灵动岛」（正文含所选模式名，按钮「确定应用」「取消」）；确认后分别走 `disable`（块 0x323c4c）和 `enableWithMode:`（块 0x323f58）。函数本身还调了一次 `setDynamicIslandSimulationEnabled:`（0x320d70）。
- `resolutionApplyTapped`（0x325ef8）：同样的 0xe5c5ec(2, 16, 1, 0) 闸（文字「修改分辨率需要 iOS 16.1 及以上系统…」）；弹「应用分辨率」，正文「预设：%@ (%ld×%ld) / 当前原生：%.0f×%.0f / 修改后设备将自动注销重启，请耐心等待。/ 如果出现黑屏/花屏等异常，请重新注销恢复。」，按钮「确定应用」「恢复默认分辨率」「取消」；前者走块 0x3281f0（`applyResolutionWithWidth:height:`），后者走块 0x328980（`restoreDefaultResolution`）。
- `updateResolutionPresetButtonTitle`（0x325290）、`buildResolutionPresetMenu`（0x3241ac）：菜单项文字格式 `%@ — %ld×%ld`，图标名 `ipad` / `iphone`。

## 3. 分辨率预设表【读】

`resolutionPresets` 在解释器里逐项把 `{名字, 宽, 高}` 装进 `NSValue`，顺序如下（2026-10-22 缺的第 4 项标签这次读到了：`15Pro / 14Pro (灵动岛)`）：

| # | 标签 | 宽×高 |
|---|---|---|
| 0 | iPhone 16 Pro Max | 1320×2868 |
| 1 | iPhone 16 Pro | 1206×2622 |
| 2 | 15ProMax / 14ProMax | 1290×2796 |
| 3 | 15Pro / 14Pro (灵动岛) | 1179×2556 |
| 4 | 13ProMax / 12ProMax | 1284×2778 |
| 5 | 13Pro / 12Pro | 1170×2532 |
| 6 | 13mini / 12mini | 1080×2340 |
| 7 | XS / X | 1125×2436 |
| 8 | iPad Pro 12.9" | 2048×2732 |
| 9 | iPad Pro 11" | 1668×2388 |

## 4. 位置与缩放【读】

MangoPanda 里应用 `PillGlass.PosAdjust/PosX/PosY/PosScale` 的函数（0x515624，1426 条指令）：取视图的 `layer` 和 `bounds`；`fmaxnm(bounds.height, 1.0)`；`anchorY = 42.0 / that`（常量 `mov x13, #0x4045000000000000` 在 0x515ad8，即 42.0）；`setAnchorPoint:`（x 取 0.5，y 取上面的值）和 `setPosition:` 补偿；`CGAffineTransformMakeScale` 做缩放并用 `CGAffineTransformEqualToTransform` 避免重复写；`setCenter:` 做 PosX/PosY 的平移。读偏好的键：`PillGlass.PosAdjust`、`PillGlass.PosX`、`PillGlass.PosY`、`PillGlass.PosScale`。

【缺】被调节的视图具体是哪一个（用 42 除视图自己的高度，说明它高得多，推测是满高的透传视图）；设置页里三个滑块的取值范围（滑块在 `MangoOSPrefs` 里建，文字串是经间接引用取的，这次没追到）。

## 5. 没做的功能的线索【读】

- 消息岛：`MangoPillManager`（`showPillForBundleID:primaryText:secondaryText:notification:`、`dismissPill`、`handleAppForegroundChange:`、`handleLockStateChange:`、`handleInterfaceOrientationChange:`）和 `MangoPillElement`（实现 SystemAperture 元素协议：`layoutAxis`、`preferredLayoutMode`、`leading/trailing/minimal/detachedMinimal/primary/secondary/action ContentViewProvider`、`handleElementViewEvent:` 等；`replyAction`、`openSplitView`、`openAppFullscreen`、`shrinkToMini`、`delayCancel*`）。挂钩：`SBSystemApertureViewController` 的 `_shouldSuppressElement:allowsSuppressionForSystemChromeSuppression:` 和 `_handleResizePan:`，以及 `NCNotificationSeamlessContentView`、`SBNotificationPresentableViewController`（2026-10-22 读）。
- 玻璃：`MangoOSRendering` 在 backboardd 里挂 QuartzCore 滤镜分发，内嵌 Metal 着色器，`go.mangoos.island` 滤镜；`MangoPanda` 在 SpringBoard 里用 `method_setImplementation` 换 `SAUIElementView`、`SBSystemApertureSceneElement`、`_SBGainMapView`、`_SBSystemApertureMagiciansCurtainView` 等的方法（见 `E:\mango-beta12-rea\REPORT.md` 第 1、2.3 节）。
- 音量滑条、频谱、分屏快捷行：`MangoMenuViewController` 里对应的开关方法（`islandVolSliderChanged:`、`islandSpectrumChanged:`、`islandSplitRowChanged:`、`islandStyleTapped` 等）和配置键 `MediaVolume.DynamicIsland`、`IslandSpectrum.Enabled/Bounce/ArtworkPulse/AlbumColor/Style`。频谱的音频电平来源没有读到【缺】。

## 6. 复现

脚本在 `E:\mango-island-extract\scripts`（本轮新写）和 `E:\mango-beta12-rea\scripts`（2026-10-22 的解释器 `armemu.py`、Mach-O 解析 `machoq.py`），都用 `python -I`：

```
python -I -X utf8 E:\mango-island-extract\scripts\emu_strs.py <MangoHello.dylib> 31f134 0      # 模式按钮标题（第三个参数是调用返回值）
python -I -X utf8 E:\mango-island-extract\scripts\emu_strs.py <MangoHello.dylib> 320960 1      # 应用按钮的流程与弹窗文字
python -I -X utf8 E:\mango-island-extract\scripts\emu_strs.py <MangoHello.dylib> d08e1c 1 900000   # 分辨率预设
python -I -X utf8 E:\mango-island-extract\scripts\emu_isenabled.py                             # isCurrentlyEnabled 的组合表
python -I -X utf8 E:\mango-beta12-rea\scripts\armemu.py <MangoHello.dylib> "d03144:x2=1;ret=1"  # enableWithMode: 的调用参数
```

菜单整段的解释器输出存在 `E:\mango-island-extract\notes\hello_viewDidLoad_emu.txt`。
