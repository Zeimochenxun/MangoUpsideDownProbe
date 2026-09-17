# SystemFlipProbe 0.1.0 — 整屏反转的只读诊断

目标设备：iPhone 13 mini / iOS 16.5 / Dopamine RootHide。

这是只读诊断包：读取显示服务器、SpringBoard 窗口和坐标转换，写入两份日志。**它不会改变显示方向，不会修复倒置，也不处理或生成触摸。** 未在真机运行验证；构建通过仅证明编译和包结构检查通过。

## 为什么改走这一条路线

已核对 UpsideDowned 开源源码和上传的 arm64/arm64e 二进制：它放开 SpringBoard 的方向限制，没有直接设置最终显示变换。下一步要判断：倒置时系统窗口如何旋转、CAWindowServerDisplay 是否改变方向，以及系统上下文之间的坐标转换如何变化。详细地址和证据见 `docs/UPSIDEDOWNED_REVIEW.md`。

采集使用真实的公开运行时头文件所列 getter；每次调用前核对设备上的 Objective-C 参数及返回类型。不匹配就记录 SKIP。只调用 `serverIfRunning`，不创建显示服务器。不调用 `setOrientation:`，不调用未经确认 ABI 的 BackBoardServices C 函数，不 Hook 系统方法。backboardd 版本不链接 UIKit。

## 安装前：准备恢复

1. 先保证另一台设备能通过 SSH 进入手机的 RootHide 越狱环境，并能在提权终端运行 `dpkg`。保持连接。没有这一条件，先不要测试向 backboardd 注入的新包。
2. 记录卸载命令：`dpkg -r com.chenxun.systemflipprobe`。必须在手机的 RootHide 环境、具有包管理权限的终端执行；不是在电脑本地执行。
3. 若注入后黑屏或失去触摸，但 SSH 仍在线，执行上述卸载命令，然后通过你已验证的方式重启用户空间。删除磁盘上的 dylib 不会立即卸载进程中已经加载的代码。
4. 若 SSH 也不可用：iPhone 13 mini 快按音量加、快按音量减，再持续按住侧边键直到 Apple 标志。Dopamine 重启后需要重新越狱；重新越狱时先关闭 tweak 注入，再卸载本包。不要仅依赖 SpringBoard 安全模式来处理 backboardd 问题。
5. 如需手动禁用，只处理包清单中的 `SystemFlipProbeSB.dylib/.plist`、`SystemFlipProbeBB.dylib/.plist`。用 `dpkg -L com.chenxun.systemflipprobe` 查询真实位置；不要猜 RootHide 随机根目录，也不要删 Mango 文件。

读取操作仍可能暴露系统私有接口的不兼容，Objective-C 异常捕获不能拦截所有原生崩溃，因此保留上述恢复方式。

## 安装与采集

1. 若正在使用旧的 MangoUpsideDownWorld / MangoUpsideDownFix，先停用它们，排除它们添加的窗口和手势变换。保留已购买的 Mango 和原来的 UpsideDowned。
2. 从压缩包的 `packages/` 安装唯一的 `.deb`，用你当前的 RootHide 包管理器。不要把源码、plist 或 dylib 直接拖进系统目录。包原生按 RootHide Theos 编译，无需再次从 rootless 转换。
3. 本包没有安装后强制重启脚本。安装后使用当前环境已验证的“重启用户空间”方式使 SpringBoard 与 backboardd 都重新加载；只重启 SpringBoard 可能不会加载 BB 模块。或者重启设备后重新越狱。
4. 在手机上保持桌面可见，从另一台设备的 SSH 终端运行下面的命令。每次保持对应状态至少 6 秒。命令中的标签只是你对现场状态的记录，不会切换方向。

```sh
systemflip-capture portrait
```

将手机倒置，确认原 UpsideDowned 已使桌面倒置，保持桌面可见，再执行：

```sh
systemflip-capture upside-down
```

转回正常竖屏再执行一次 `systemflip-capture portrait`。如需补充横屏和锁屏，分别执行 `systemflip-capture landscape`、`systemflip-capture lock-screen`。

每次请求采集 0、2、5 秒三个快照。命令显示 Capture requested 只证明通知已发出，必须检查两份日志都有本次 CAPTURE/END 行。如果提示 command not found，用包管理环境中的 `dpkg -L com.chenxun.systemflipprobe` 找到 `systemflip-capture` 的实际路径；不要照抄另一台设备的 RootHide 路径。

## 需要返回的内容

- `/var/mobile/Library/Logs/SystemFlipProbe-SpringBoard.log`
- `/var/mobile/Library/Logs/SystemFlipProbe-backboardd.log`
- 对应正放、倒置状态的屏幕照片，以及是否开启方向锁定的说明。

若该目录无法写入，模块会尝试 `/tmp/` 下同名文件。日志权限为 0600，backboardd 的文件可能需要提权的 Filza/SSH 读取。没有 BB 日志时先确认是否加载，不能据此推断系统没有显示服务器；不要扩大到所有进程注入。

日志最多约 2 MiB，达到上限会清空后继续。没有截图、窗口内容、键盘文字、原始触摸记录或网络上传；只记录类名、几何、方向、方法类型和上下文标识。

## 结果如何使用

- SB 场景方向变了、BB 显示方向不变：支持当前在客户端窗口/场景层转动的判断，仍要检查窗口矩阵。
- BB 显示方向也变了：比较变更时机及 MAP 记录，确认是否已有显示层参与，避免再次转动造成抵消。
- MAP 的往返结果一致：只证明两种上下文转换自洽，**不证明物理触摸已被正确反转**。
- `serverIfRunning=nil`、缺方法或 SKIP：保留日志作为下一轮定位依据，不自动尝试创建服务器或调用替代 setter。

下一阶段才是有超时恢复的短时显示反转试验，并核验物理触摸、边缘手势、锁屏、唤醒和应用切换。仅发现 `setOrientation:` 或旋转常量不能保证 iOS 16.5 内屏和全部覆盖层都支持该用法。

## 构建

使用 RootHide 的 Theos、兼容现代 arm64e ABI 的 Apple clang，以及 iOS 16.5 SDK：

```sh
make clean
make package FINALPACKAGE=1
```

`THEOS` 指向你实际安装的 RootHide Theos。工程使用 `THEOS_PACKAGE_SCHEME=roothide`、`ARCHS=arm64e`。不要把普通 rootless 包仅改 Architecture 字段当成转换完成。GitHub 工作流负责构建、检查注入范围/载荷/签名区域/架构，记录 SDK 校验值及编译器版本。

## API 来源

- [UpsideDowned 源码，固定提交](https://github.com/34306/upsidedowned/blob/b542ebe44305d12e19126d7d5481e6f4ab05615a/Tweak.xm)
- [CAWindowServer](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/QuartzCore.framework/CAWindowServer.h)
- [CAWindowServerDisplay](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/QuartzCore.framework/CAWindowServerDisplay.h)
- [UIWindow `_contextId`](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/UIKitCore.framework/UIWindow.h)
- [RootHide Theos](https://github.com/roothide/theos)

这些公开头文件不是本机 iOS 16.5 的 ABI 保证；本包将设备实际方法类型写进日志，并严格核对后才调用 getter。
