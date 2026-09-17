# Mango 系统级倒置核查：2026-09-17

**状态：完成最新源码审查和新增二进制的定向反汇编；尚未实现或验证整屏显示与触摸的成对反转。本次没有生成“系统级修复成功”的安装包。**

目标是 iPhone 13 mini、iOS 16.5、Dopamine RootHide 上完整倒置显示及输入，避免只改灵动岛 UIWindow。所有输入原文件保持未修改；分析不涉及授权、收据、账号或付费机制。证据包不包含付费 dylib 原件。

## 1. GitHub 最新代码

检查仓库 `Zeimochenxun/MangoUpsideDownProbe` 的可见分支 `main`、`world-alpha1`、`world-alpha2`。最新 World 位于 `world-alpha2`，实际版本 **0.8.0~alpha8**，提交 **97f3babb2699b1162aa6b2218824f135d9cff7db**，不是分支名暗示的 alpha2。

完整阅读了该版本的 Tweak.xm、WorldMath.h、control、README.md、EVIDENCE.md、构建工作流。当前逻辑包括：

- 用 Mango 自身的 `+[DecoratedAppSceneView mango_currentInterfaceOrientation]` 判定方向 2。
- 旋转 `SBSystemApertureWindow`，规范化 `_SBSystemApertureContainerViewContentView` 的旋转；这是单个系统窗口范围。
- Hook `UIPanGestureRecognizer translationInView:` / `velocityInView:`，识别器挂载视图在被转动的 root 下时，把 x、y 均取反。
- 注入过滤仍然只有 SpringBoard，没有 display server / backboardd 显示与 HID 映射实现。

### 已确认的代码问题

`HookTranslation(self, cmd, view)` 把 `view` 交给原实现，但后续 `TurnDelta` 不接收这个目标坐标空间，只检查 `self.view` 的归属。因此它把所有这些读数都当成固定屏幕空间的增量，是没有依据的。`translationInView:` 的结果取决于调用者指定的 view；若读数已在正确的旋转坐标中，再取反就可能造成二次反转。

alpha8 文档中的“唯一自洽解释”“前四版失败排除了所有层级符号问题”“这一定不是回归”等结论均超出了已有证据。旧测试中没有 `GESTURE` 行也不能证明具体调用方、坐标空间或实际失败原因。这里不把这些文档推断继承为事实。

## 2. 本次上传文件与过滤范围

| 文件 | 字节 | 已解析情况 / 注入过滤 |
|---|---:|---|
| mango(1).dylib | 1594592 | 与最初 mango.dylib 的 SHA256 完全一致；arm64e |
| mangoos.dylib | 706992 | arm64e；27 个 ObjC 类、1 个 category、530 个方法；UIKeyboard、MediaRemoteUI、SpringBoard |
| mangoUIKit.dylib | 144192 | arm64e；2 个 ObjC 类、53 个方法；plist 列出 UIKit、backboardd、SpringBoard、微信及 mediaserverd executable |
| MangoOSRendering(1).dylib | 123520 | arm64e；无 ObjC 类；backboardd |
| MangoOSPrefs.plist | 510 | 偏好设置入口，指向 MGPRootListController；不是 tweak 注入过滤 |

精确文件大小和 SHA256 以 `evidence/input_manifest.json` 为准。plist 的过滤列表表示声明的匹配目标，不等同于已证明设备上每个目标都成功注入。

新增 Rendering 与旧版 UUID 相同；全部已解析 section 的字节内容相同。整文件仅 40 个字节不同，分布在头部/节描述附近及签名区。没有因此发现一套新的旋转代码。

## 3. mangoos：真实系统手势 Hook 调用链

以下地址均为本次 `01-mangoos.dylib` 内的未滑移 VM 地址，不能直接作为其他版本的运行时地址。

```text
初始化函数 0x35c20
  0x3638c: 引用 SBSystemApertureResizeGestureRecognizer
  0x363b8: MSHookMessageEx(touchesBegan:withEvent:, 0x38148, ...)
  0x363e4: MSHookMessageEx(touchesMoved:withEvent:, 0x381e0, ...)
  0x363ec: 引用 SBSystemApertureLongPressGestureRecognizer
  0x36410: MSHookMessageEx(touchesMoved:withEvent:, 0x38278, ...)
          ↓
三个 Hook 均调用 0x3a188
          ↓
dispatch_once block 0x38310
  notify_register_check("go.mangoos/mediavolume.touch", ...)
          ↓
0x3a188: notify_get_state + time(NULL)
  状态时间戳非零且 0 <= 当前时间 - 时间戳 < 6 秒时返回真
          ↓
Hook: 真 → setState:5；假 → BLRAAZ 调用保存的原实现
```

**已证实：** 这里是依据通知状态暂时使系统岛手势识别器进入失败状态的分支；本分支没有坐标取反、方向读取或显示变换。

**高度可能：** 用于媒体音量交互的手势冲突抑制，依据通知名称和失败行为；不能据此断言用户当前故障一定由它导致。

这也证明此前“只剩 pan 基类入口可查”的方向太窄：新附件直接给出了真实系统识别器类名和 touches 入口。

另有真实窗口几何链：`0x49334` 注册 `SBSystemApertureWindow layoutSubviews` Hook，替代函数 `0x4ad78` 调用原实现后按配置比较/设置 transform 与 center。World 同时改该窗口，存在需要核实的共同写入路径。仅静态存在不证明该配置在用户设备上开启。

## 4. mangoUIKit：显示查询不等于显示反转

本镜像存在真实字符串：

- `__XGetDisplayInfo`
- `__ZN2CA12WindowServer6Server16get_display_infoEPNS_6Render6ObjectEPvS5_`

调用链：

```text
初始化 0xe0f8 中的 0xe4dc–0xe5f8
  定位 QuartzCore 内 get_display_info，扫描指令以提取字段偏移
  通过 0xf1b4 安装两个替代函数
       ↓
__XGetDisplayInfo 替代函数 0xf210
  检查消息 / trailer，设置线程局部状态，调用原函数，再清理状态
       ↓
get_display_info 替代函数 0xf388
  先调用原函数；在条件满足时修改其返回缓冲区
  0xf3e8: ldr w9, [x19, x8]
  0xf3ec: and w9, w9, #0xfffffffb
  0xf3f0: str w9, [x19, x8]
```

**已证实：** 该分支清除返回字段的 bit 2（0x4）。本轮没有确认字段语义，不能把它命名成 orientation、触摸方向或 display transform。这里也没有观察到设置显示旋转矩阵的调用。

在 backboardd 注入、依赖 QuartzCore 或名称包含 display，均不足以证明它负责全屏旋转。

## 5. MangoOSRendering：玻璃采样方向

该镜像内 Metal shader 的 `samplingOrientation` 分支对纹理 UV 进行倒置或横屏换算；`coverOrientation` 分支同样处理背景采样/镜片像素。**这些属于局部玻璃渲染，不是把整个显示输出和触摸输入旋转。** 已解析 section 与旧文件完全相同。

## 6. 系统级入口：找到候选，但不能拼成已验证修复

这部分属于系统框架证据，**不是声称以下 API 存在于 Mango 的实现中**。

- 本地 iOS 16.5 SDK 的 QuartzCore.tbd 导出 `CAWindowServer`、`CAWindowServerDisplay`、`kCAWindowServerOrientation_PortraitUpsideDown` 等。
- 公开的运行时头文件有 `CAWindowServerDisplay orientation` / `setOrientation:`，及 `convertPoint:toContextId:` / `fromContextId:`。这支持“存在显示服务器级方向入口”这个研究方向，但头文件不证明 iOS 16.5 手机上的实现语义与触摸更新时机。
- BackBoardServices.tbd 有 `BKSHIDServicesSetDeviceInterfaceOrientation` 等符号。导出符号表不提供 ABI、方向枚举语义或触摸重映射的证明，不能只凭符号名声明一个函数指针就调用。

参考原始记录：

- [CAWindowServerDisplay 运行时头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/QuartzCore.framework/CAWindowServerDisplay.h)
- [CAWindowServer 运行时头文件](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/QuartzCore.framework/CAWindowServer.h)
- [原生项目中使用显示方向接口的例子](https://github.com/steventroughtonsmith/mobilex/blob/de4bd3538b5d5344ed4e197f8849d67cb3c6d2b7/Trunk/MobileX-1407/MXController.m)（旧版 TVOut 用途，不能当作 iOS 16.5 内屏可用性的证明）

真正的全局方案需要明确：最终显示变换 F 与触摸到原逻辑空间的逆变换 F⁻¹；还要避免原倒置插件、World 与显示服务器重复旋转。切换时必须处理正在进行的多指触摸、屏幕边缘手势、锁屏、唤醒、键盘和横屏回退。仅把 `portraitUpsideDown` 数值强制返回，不保证这些组件同步。

## 7. 明确的缺口与下一份输入

这 9 份附件均属于 Mango；**没有当前负责倒置整个屏幕的插件本体**。目前不知道原倒置插件在哪一层写方向、是否已改 HID、如何判断启停，也未取得 iOS 16.5 对应低层函数的实现证据。

下一份最小输入是：**设备上当前倒置插件的 `.dylib` 和同名注入 `.plist`；若有多个 dylib，一并提供**。若没有单独倒置插件、而是 Mango 自带开关，需要提供该开关的准确名称/设置截图，以便从本次已有二进制中追踪正确入口。

收到这份输入前，本次可交付的是可复核的分析和地址链；不是一个伪装成完成品的全局反转 dylib。没有修改手机，没有更改 main / world-alpha2，没有生成新安装包，也不建议把更早 alpha 包误当成本轮成果。
