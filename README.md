# Mango 整合补丁 1.0.0 alpha5

一个安装包、一个设置入口，整合指定的四个补丁。需要已经安装原版 Mango；不包含 Mango 主插件。

**alpha5 简化首页：** 首级菜单删除所有功能及版本小字描述，最上方只保留一行“本插件为mango插件的自改补丁，仅自用”。分组标题、总开关、四个模块开关及两个参数入口保留；应用方式仍可从“如何应用开关更改”查看。

**alpha4 修复开关保存失败：** alpha3 通过 CFPreferences 保存，却使用未转换的 `/var/mobile/Library/Preferences` 路径校验与回读。RootHide 会重定向非系统偏好域，两个位置并不一致；旧校验可能将成功写入判为失败并回滚。本版由设置首页、玻璃页和加载器共用 `src/SuitePreferences.m`，通过 `jbroot` 访问同一份配置，不再混用偏好接口和固定文件路径。

开关文件位于 RootHide 根内的 `/var/mobile/Library/Application Support/MangoSuite/settings.plist`，由设置进程创建，原子写入后从同一位置验证。更改一项会保留其他项及未知键。找不到新文件时，优先读取 RootHide 内的旧整合偏好文件，再兼容旧的未重定向文件；首次成功修改时迁移整份字典。损坏或不可读取的配置不会被默认值覆盖。真实保存失败会报告错误及文件位置。

保留 alpha3 的首页修复：使用 `NSPrincipalClass = MangoSuitePrefsController`，并明确先编译首页控制器。打开“设置 → Mango 整合”后先显示总开关和四个独立模块开关；两类参数页面从首页进入。

保留 alpha2 的安装目录修复：显式写入所有父目录，目录权限为 `0755`、所有者为 `root:root`。四个原补丁的二进制与原输入逐字节一致。

如果上一版安装失败，可直接安装本版，无需手动创建目录。成功后再重新启动用户空间。

| 模块 | 保留版本 | 设置开关 |
|---|---|---|
| IdleIsland | 1.1.9.2~alpha2 | 静止灵动岛与过渡修复 |
| AdaptiveColor | 0.1.3 | 背景颜色自适应 |
| MangoUpsideDownWorld | 1.2.0 | 倒置方向修复 |
| MangoSplitUpsideDownFix | 0.1.1-alpha2 | 分屏倒置修复 |

适用环境：**iOS 16.5、RootHide、arm64e，原补丁所支持的 Mango Beta7-1**。不适用于普通 rootless/rootful 或其他 iOS 版本。Split 的原版 Mango UUID 检查保持不变，不匹配时不会强行修改窗口。

## 安装和使用

1. 使用 Sileo 等安装 `packages/MangoSuite-1.0.0-alpha5-RootHide-arm64e.deb`。可以直接覆盖旧版整合包，无需手动改文件权限。安装器会提示替换四个独立补丁；还会阻止与旧 `MangoUpsideDownFix`、`MangoOrientationProbe` 同时安装。确认操作列表保留 **Mango 主插件**。
2. 在越狱工具中执行 **重新启动用户空间**。
3. 打开系统设置 → **Mango 整合**。页面依次为总开关、灵动岛外观、旋转与布局。
4. 按需调整四个开关。总开关关闭时保留各子开关的选择。**本页开关更改均需重新启动用户空间**；仅 Respring 不足以重载 backboardd 中的自适应渲染模块。
5. 玻璃及自适应参数沿用原来的参数刷新方式。自适应开启时，基础色调强度不可调，请在自适应参数页调整明暗不透明度。光斑强度属于 Mango 全局设置，也会影响其他玻璃区域。

首次没有整合设置时默认启用四项。原来的参数不会重置。已有应急停用文件会使相应开关显示关闭；手动打开时面板会尝试清除该文件，失败会提示，避免显示已开而实际停用。

## 整合方式

- 四个原模块的已签名二进制保持原样，输入文件和模块 SHA-256 记录在 `inputs/sources.json` 及交付 manifest 中。没有以 1.2.1 源码替代 World 1.2.0，也没有以 AdaptiveColor 0.1.3.3 实验包替代 0.1.3。
- 一个新加载器在进程启动时读取整合配置，按总开关和四个子开关决定加载哪些模块。三个进程使用同一份移动用户配置，避免 backboardd 用户身份与 CFPreferences 缓存产生差异。不会在运行中卸载已经挂钩的方法。
- AdaptiveColor 仅进入 backboardd；其余三项仅进入 SpringBoard。World 针对系统灵动岛窗口，Split 针对精确 UIWindow 类的 Mango 分屏窗口，保留原有作用范围。
- 原动态库放入 `Library/MangoSuite/Modules`，不保留它们的独立注入 plist。该目录的 `.jbroot → ../../..` 使原 RootHide 相对依赖仍能找到越狱根。统一设置 bundle 也包含自身的 `.jbroot → ../../..`，用于本版新增的 libroothide 依赖。
- 唯一顶层设置入口是 Mango 整合。玻璃页根据精确 Idle 参数页源码整理，自适应参数页使用原版 0.1.3 UI 二进制。

## 验证和限制

`tests/policy.c` 检查 512 种开关、应急标记和旧冲突状态在三个进程范围中的组合。`tests/check_suite.py` 对最终安装包检查四个原模块逐字节一致、arm64e ABI、签名代码页、唯一设置入口、RootHide 链接及包冲突声明。

`tests/check_directories.py` 检查实际 DEB 的原始 tar 目录项与先后顺序。`tests/test_dpkg_install.py` 在 Linux 的隔离根目录内调用真实 dpkg，使用与交付包完全相同的 14 个载荷路径及权限、惰性文件内容，覆盖旧版缺目录错误、首次解包、失败后重试、升级保留旧偏好与新配置四项，并验证两处依赖链接均解析到安装根。该测试验证安装包结构，不执行 iOS 动态库；不代表真机功能测试已完成。

`tests/test_settings_entry.py` 在 macOS 上将实际首页/玻璃页源码配合最小界面类替身编译为测试 bundle，调用真实 NSBundle，复现错误字段导致直接打开玻璃页，并验证修复后加载首页、生成五个开关和两个参数入口。保存回归还编译实际共享存储代码，以临时目录模拟 `jbroot` 的路径映射：复现 alpha3 写入成功却报错回滚，检查实际首页 setter 对全部 32 种选择的独立保存、新控制器回读、独立进程回读、玻璃页联动、旧配置迁移，以及目录不可写和配置损坏时保留原数据。它使用真实 Foundation 文件读写，不模拟 iPhone 的显示、触摸或越狱沙盒。

编译和包结构验证不能代替真机测试。此版本标为 alpha5；交付时应以 `packages/verification.json` 和构建日志为准。尚需真机验证开关保存后退出设置再进入、重新启动用户空间后开关生效，以及通知上划清除、灵动岛展开收拢、音乐活动切换、正反转向和分屏拖动。

RootHide 路径依据：[开发者的文件路径 API](https://github.com/roothide/Developer/blob/main/interface.md)、[共享文件存放说明](https://github.com/roothide/Developer/blob/main/entitlements.md)、[偏好重定向实现](https://github.com/roothide/Bootstrap-basebin/blob/main/bootstrap/prefshook.m)。

## 回退

关闭总开关并重新启动用户空间可以停用四个整合模块。需要回到独立补丁时，先卸载 Mango 整合，再安装 `inputs/` 中四个原包并重新启动用户空间。原 Mango 参数不会在卸载时清空。

## 构建

macOS CI 只构建新的加载器及统一设置 bundle，使用 RootHide Theos、固定校验的 iOS 16.5 SDK 和 Xcode arm64e 工具链。原模块与本地最终包不上传构建分支。

下载构建 helper 后，在此目录执行：

```text
python tools/assemble.py --helper-deb <helper.deb>
python tests/check_suite.py packages/MangoSuite-1.0.0-alpha5-RootHide-arm64e.deb
```

`helper` 是中间构建产物，不是供设备安装的完整插件。请只安装最终 MangoSuite 包。
