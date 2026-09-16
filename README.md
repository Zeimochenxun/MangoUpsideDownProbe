# MangoUpsideDownFix 0.1.0-alpha1

独立的实验性位置修复工程，目标是 **iPhone 13 mini / iOS 16.5 / Dopamine RootHide**，配合已购买的 Mango 和现有 Upsidedowned。它不包含 Mango 原始二进制，也不修改其配置或授权。

这次交付的是源码及构建流程，**不是已经真机验证的安装包**。工程内 `VALIDATION.md` 区分已完成检查与尚未完成的验证。

## 它具体修什么

真机日志已确认：倒置时 Mango 读到方向 2，内容层已转 180°，但外层 `SBSystemApertureContainerView` 仍在原来的物理顶部。

本工程只对从 Mango 布局回调确认的容器实例加位置补偿：将其矩形在屏幕固定坐标中沿水平中线移动到对侧，保持内部已有旋转。不会给内容再旋转一次，也不改 `alpha`。正常竖屏和横屏撤销本工程的位移。

**这只验证了一个待实机检验的修复方向，不能预先保证动画和触摸正确。** 当前仅覆盖已确认的系统 aperture 路径，不覆盖 Mango 的备用 UIWindow。

## 编译前先准备恢复

沿用你先前已经成功连接的 SSH。先确认电脑仍能登录手机；保留一个会话。记录 Dopamine 中关闭 tweak 注入的位置，并保留当前能正常工作的 Mango、Upsidedowned。

这个新包的卸载命令是：

```sh
dpkg -r com.chenxun.mangoupsidedownfix
```

卸载后通过你当前环境已经验证可用的功能 respring。此命令只卸载 Fix，不卸载 Mango 或 Upsidedowned。

安装后可用以下只读命令记录实际安装位置：

```sh
dpkg -L com.chenxun.mangoupsidedownfix
```

如果包管理器不可用，在 Filza 按该清单把 **MangoUpsideDownFix.dylib 和 MangoUpsideDownFix.plist** 移出注入目录，再 respring。不要照搬 `/var/jb`；RootHide 的实际路径应以安装清单为准。

若 SSH 也无法连接：快速按放音量加、快速按放音量减，按住侧边键直到 Apple 标志。重启后通过 Dopamine 当前版本支持的关闭 tweak 注入方式恢复环境，再卸载 Fix。不要假定未越狱时 SSH 或 Filza 仍然可用。

### 运行时禁用开关

本工程识别真实文件系统中的空文件：

```text
/var/mobile/Library/Preferences/MangoUpsideDownFix.disabled
```

若你的 SSH shell 与先前日志一样在 RootHide bootstrap 中，已确认通过 `/rootfs` 访问真实系统，则执行：

```sh
touch /rootfs/var/mobile/Library/Preferences/MangoUpsideDownFix.disabled
```

在 SpringBoard 正常运行、主线程可执行的情况下，通常约 0.25～0.30 秒内检查到标记并撤销能够确认属于本工程的位移；本次进程内保持禁用。移除标记并 respring 才重新启用。启动前已有标记则不安装 hooks。

这不是 SpringBoard 卡死后的恢复保证；卡死或崩溃时使用卸载、关闭注入或重启。遇到 `CONFLICT` 日志时不覆盖未知 transform，应卸载/respring 恢复。

## 使用已有 GitHub Actions 构建

1. 解压后进入 `MangoUpsideDownFix` 文件夹。把**文件夹里的完整内容**放到仓库根目录，不要多套一层目录。
2. 沿用已有私有仓库也可以。替换根目录 `Tweak.xm`、`Makefile`、`control`，加入 `Geometry.h`、`MangoUpsideDownFix.plist`、`tests/`、`tools/`；将附带的 `.github/workflows/build.yml` 替换到同一路径。这些文件必须一起更新，不能只替换 Tweak.xm。
3. 提交后打开 **Actions → Build MangoUpsideDownFix (RootHide)**。它会用 macOS、RootHide Theos、iOS 16.5 SDK 构建。
4. 绿色成功后，下载 **MangoUpsideDownFix-0.1.0-alpha1** artifact，解压其中的 `.deb`。失败时不要安装残留包。
5. 核对包名称是 **MangoUpsideDownFix**、包 ID 是 `com.chenxun.mangoupsidedownfix`，不是旧 Probe。

本流程只构建和检查，不自动连接手机或安装。工程不需要修改 Mango 原版文件。

已安装 Probe 时，可通过包管理器卸载 `com.chenxun.mangoupsidedownprobe` 后进行 Fix 首轮测试，以免混淆日志。它们使用不同包名和日志路径，Fix 不会替换 Probe。

### 本地 macOS 命令

已有 RootHide Theos 和 iOS 16.5 SDK 时，在工程根目录执行：

```sh
export THEOS="$HOME/theos"
make clean
make package FINALPACKAGE=1
python3 tools/check_package.py packages/*.deb
```

Makefile 使用 `ARCHS=arm64e`、`THEOS_PACKAGE_SCHEME=roothide`。直接构建 RootHide 包，无须先构建普通 rootless 包再转换。不要使用出现 `incompatible arm64e ABI` 警告的产物；转换工具不能修复坐标算法或方法签名。

## 第一轮安装与测试

先完成上面的恢复准备，再用现有包管理器安装构建成功的 `.deb` 并 respring。Mango 和 Upsidedowned 保持原来的配置。

按下面顺序观察；出现异常先停用/卸载 Fix：

| 顺序 | 操作 | 通过标准 |
|---|---|---|
| 1 | 正常竖屏触发一次以前会显示 Mango 岛的事件 | 原有位置、文字和交互不变 |
| 2 | 倒置手机，触发相同事件 | 岛位于视觉顶部，文字正向，不在刘海一侧 |
| 3 | 点击岛、长按展开并收起 | 点击命中可见位置，动画没有闪回原来一侧 |
| 4 | 保持展开切回竖屏，再反复倒置 5 次 | 能恢复，没有累积漂移或双重旋转 |
| 5 | 左右横屏、锁屏/解锁 | 保留原有行为，不残留位移 |
| 6 | 测音乐、计时器及其他实际使用的岛内容 | 分别记录位置、展开和点击；不能用 Mango 通知一次成功代替这些检查 |

**先前出现过 Mango host `alpha=0`。** 这不等于屏幕上的整个岛都不可见，也不代表交互已被证明；Fix 不会强行把 host 变成不透明。

Fix 只追踪通过 Mango 的真实回调找到的容器。若音乐/计时器使用不同容器，或最后一个 Mango host 已从这个容器分离，它可能不受此版影响。没有观察到回调时不盲目扫描并移动所有系统窗口。

## 查看这版的日志

日志与旧 Probe 分开，真实路径为：

```text
/var/mobile/Library/Logs/MangoUpsideDownFix.log
```

在已确认的 RootHide bootstrap shell 中：

```sh
tail -n 80 /rootfs/var/mobile/Library/Logs/MangoUpsideDownFix.log
```

| 标记 | 意义 |
|---|---|
| `INSTALLED` | 已通过版本/签名检查并安装 scoped hooks |
| `TRACK` | Mango 回调已确认一个 host 和外层容器 |
| `APPLY` | 已施加位移，并核对模型坐标到达目标 |
| `RESTORE` | 撤销本工程的已知位移 |
| `SKIP` | 当前方向/几何不符合本版处理条件 |
| `NO HOOKS` | 系统版本、Mango UUID 或方法签名不匹配，本版未挂钩 |
| `CONFLICT` / `SUSPEND` | 出现未覆盖情况，停止处理该实例，需 respring 清理状态 |

`APPLY` **不代表触摸测试或动画测试通过**。日志不记录通知正文或账户信息，文件约 512 KiB 封顶循环写入。

## 设计边界

- 仅注入 SpringBoard，不注入 backboardd。
- 只接受 iOS 16.5，以及 Mango UUID `67C0D7C2-4487-3FD2-9535-067745AE4B8F`；这是一版受限实验补丁，Mango 更新后通常会停止挂钩。
- 不改方向 API、不伪造通知、不读写 Mango 配置、不改原始 dylib。
- 不写固定 y、屏幕高度或设备分辨率；按目标 window 的固定坐标和实际父视图变换计算。
- 本版只补偿垂直位置，保留 Mango/System Aperture 原有水平位置和尺寸，不额外修正其水平布局。
- 旋转和缩放来自系统，本工程只加父坐标中的平移。进入受监控的系统 geometry setter / layout 时先撤销已知位移，原方法执行后再计算。
- 这仍可能与系统动画、自定义命中测试或直接 CALayer 写入冲突。没有修改事件分发，没有证明“仅移动容器就能覆盖所有系统触摸区域”。

技术依据、已知风险和验证结果分别见 `EVIDENCE.md`、`VALIDATION.md`。

来源：[RootHide 开发说明](https://github.com/roothide/Developer)、[Theos arm64e 构建说明](https://theos.dev/docs/rootless)、[Apple 视图坐标与变换说明](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/CreatingViews/CreatingViews.html)。
