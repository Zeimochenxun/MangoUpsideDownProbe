# MangoUpsideDownProbe：仅诊断，尚未修复位置

这是与本次二进制证据对应的独立 Objective-C tweak 源码。文件名有意使用 Probe，避免将诊断工程误认为 MangoUpsideDownFix。没有提供或声称已编译、已实机验证的 dylib/deb。

## 先准备恢复，再考虑编译安装

1. 保留原始 Mango 文件、现有插件配置，以及当前能用的越狱环境。此工程不替换 Mango。
2. 在电脑上实际验证 SSH 能登录设备，并能打开两个并行会话。不要只确认“装了 SSH”。
3. 先验证 package manager 的卸载命令可用，并记录 `dpkg -L com.chenxun.mangoupsidedownprobe` 的结果。该命令须在安装后执行以获得实际路径；安装前确认 `dpkg` 可用。
4. 明确手中 Dopamine 版本关闭 tweak 注入的入口。测试前实际查看；不要依赖可能因版本而不同的安全模式手势。
5. 即使诊断代码也运行在 SpringBoard，仍可能触发 crash/respring。出现问题优先卸载本工程，不重装或修改 Mango、MobileGestalt、backboardd。

### SSH 恢复

在已确认使用 RootHide bootstrap 路径语义的 shell 中：

```sh
dpkg -r com.chenxun.mangoupsidedownprobe
```

先移除包，再使用你当前越狱环境已验证可用的 respring 功能。不要先反复重启 backboardd。

如果包管理器不可用，在 Filza 中按安装清单定位本工程的 `MangoUpsideDownProbe.plist` 和 `MangoUpsideDownProbe.dylib`，把它们移出注入目录（存入单独的禁用备份目录），然后 respring。不要只凭路径猜测删除文件；不要移动任何 Mango 原文件。

代码还检查一个自定义禁用标记，其**真实根文件系统路径**为：

`/var/mobile/Library/Preferences/MangoUpsideDownProbe.disabled`

创建该空文件会停止诊断采样；下次 SpringBoard 启动不再安装本工程的 hooks。已安装的 hooks 仍调用原方法，直到进程退出，不尝试运行中卸钩。

RootHide bootstrap 工具可能将 `/` 映射为 jbroot。其官方文档规定可经 `/rootfs` 访问真实系统目录。因此，只有确认该 shell 确实采用该语义后，才使用：

```sh
touch /rootfs/var/mobile/Library/Preferences/MangoUpsideDownProbe.disabled
```

Filza 中显示的实际路径与上述 shell 路径可能不同，不要照搬 `/var/jb`。

如果 SSH 也不可达，iPhone 13 mini 强制重启操作为：快速按放音量加、快速按放音量减，再按住侧边键直到 Apple 标志。Dopamine 是 semi-untethered 越狱；完整重启后先保持未重新启用 tweak 注入的状态，再通过当前版本支持的关闭注入方式恢复、卸载本工程。不能保证用户尚未验证的 SSH/Filza 在未越狱状态可用。

## 工程做什么

- 仅注入 `com.apple.springboard`。
- 启动后在主队列最多等待 20 秒，确认加载的 `mango.dylib` UUID 完全匹配本次样本。
- 验证实际方法签名。四个 Mango hook 的签名任一不匹配就不安装。
- Hook `MangoPillManager` 的 `handleInterfaceOrientationChange:`、`showFallbackPill:`。
- Hook `MangoPillElement` 的 `layoutHostContainerViewDidLayoutSubviews:`、`preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:`。
- 若运行时签名匹配，观察 `SBSystemApertureViewController` 的 `viewWillAppear:`；若它已出现，则用有限深度的公开 view-controller 树查找现有实例。
- 记录 Mango 缓存方向、UIKit 方向、windowScene 方向、bounds、safe area、UIView/CALayer transform，以及映射到 screen.fixedCoordinateSpace 的三个基点。
- 所有原方法原样调用一次，边距返回值原样返回；不设置 frame/center/transform，不更改方向 API，不修改触摸分发，不发送虚假系统通知。
- 不主动开始 UIDevice 方向采样。因此 `deviceOrientation=0` 是允许的，不能据此判断传感器或倒置插件失效。
- 记录布局参数和类名，不读取通知正文、账号或授权信息。

日志文件真实路径：

`/var/mobile/Library/Logs/MangoUpsideDownProbe.log`

同时写系统日志，前缀 `[MangoUDProbe]`。日志文件约 1 MiB 封顶，超过会清空本工程的日志重新写。周期采样每 2 秒一次，持续 10 分钟；旋转通知及相关 hook 也可触发采样。没有“后台永久运行”的额外进程。

`new-window-during-showFallbackPill` 是在该方法执行期间新出现的窗口候选；仍应结合 160×44、y=10 等证据识别，不能仅凭“新增”就断定归属。未观察到 host 回调不等于没有系统灵动岛。

## 编译前提和命令

使用支持当前 arm64e ABI 的 macOS/Xcode 工具链及 RootHide Theos，SDK 至少支持 iOS 16。`ARCHS=arm64e` 是 Mach-O CPU 架构；Debian `Architecture` 是包兼容标记，二者不是一个概念。打包后检查实际 `Architecture` 与目标设备的 `dpkg --print-architecture` 一致，不使用强制安装参数。

```sh
make clean
make package FINALPACKAGE=1
```

Makefile 已设置 `THEOS_PACKAGE_SCHEME=roothide`。没有 `after-install` 脚本，也没有自动安装步骤。生成包后先检查包清单、注入 plist、加载依赖、arm64e 架构和签名，再由包管理器安装。

直接为 RootHide 编译优于先生成普通 rootless 包再转换。转换工具不能补上错误的 arm64e ABI、方法签名或坐标算法；本工程不需要改 Mango 原包，不应把 `/var/jb` 硬编码到代码。

来源：[RootHide 开发文档](https://github.com/roothide/Developer)、[RootHide 路径规则](https://github.com/roothide/Developer/blob/main/roothide.md)、[Theos arm64e/rootless 说明](https://theos.dev/docs/rootless)、[RootHide Dopamine](https://github.com/roothide/Dopamine2-roothide)。

## 采样矩阵

在恢复手段就绪、源码成功构建并检查后，分次记录：

| 场景 | 采样重点 |
|---|---|
| 正常竖屏、Mango 开启 | 系统 aperture 是否存在；正常几何基线 |
| 打开倒置插件、稳定 180° | Mango 缓存/scene/statusBar 是否真的变成 2；三个坐标基点是否改变 |
| 倒置状态触发一条无敏感内容的通知 | 是否调用 `showFallbackPill:`；outsets；内容是否被撤下 |
| 展开、收起、点击、滑动 | 人工记录命中位置和动画方向；日志本身不能验证触摸成功 |
| 关闭倒置、恢复正向 | 几何和内容是否恢复基线 |
| 左右横屏 | 保留原行为的对照 |
| 临时关闭 Mango 玻璃效果后重复倒置 | 区分宿主坐标错误与纯纹理采样错误 |

这份 Probe 不修复任何场景。只有在确定当前显示路径以及倒置插件改变的坐标层之后，才应把对应变换写入正式的 MangoUpsideDownFix。
