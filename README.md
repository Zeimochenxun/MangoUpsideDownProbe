# Mango 整合补丁 1.0.0 alpha2

一个安装包、一个设置入口，整合指定的四个补丁。需要已经安装原版 Mango；不包含 Mango 主插件。

**alpha2 修复首次安装失败：** alpha1 的 Debian 载荷缺少显式目录项，dpkg 在新目录下创建 `.dpkg-new` 文件时报 `No such file or directory`。本版补齐所有父目录，目录权限为 `0755`、所有者为 `root:root`，并在文件之前写入。四个补丁、加载器和设置页的二进制均与 alpha1 相同；只修正打包结构及整合包版本。

如果上一版安装失败，可直接安装本版，无需手动创建目录。成功后再重新启动用户空间。

| 模块 | 保留版本 | 设置开关 |
|---|---|---|
| IdleIsland | 1.1.9.2~alpha2 | 静止灵动岛与过渡修复 |
| AdaptiveColor | 0.1.3 | 背景颜色自适应 |
| MangoUpsideDownWorld | 1.2.0 | 倒置方向修复 |
| MangoSplitUpsideDownFix | 0.1.1-alpha2 | 分屏倒置修复 |

适用环境：**iOS 16.5、RootHide、arm64e，原补丁所支持的 Mango Beta7-1**。不适用于普通 rootless/rootful 或其他 iOS 版本。Split 的原版 Mango UUID 检查保持不变，不匹配时不会强行修改窗口。

## 安装和使用

1. 使用 Sileo 等安装 `packages/MangoSuite-1.0.0-alpha2-RootHide-arm64e.deb`。安装器会提示替换四个独立补丁；还会阻止与旧 `MangoUpsideDownFix`、`MangoOrientationProbe` 同时安装。确认操作列表保留 **Mango 主插件**。
2. 在越狱工具中执行 **重新启动用户空间**。
3. 打开系统设置 → **Mango 整合**。页面依次为总开关、灵动岛外观、旋转与布局。
4. 按需调整四个开关。总开关关闭时保留各子开关的选择。**本页开关更改均需重新启动用户空间**；仅 Respring 不足以重载 backboardd 中的自适应渲染模块。
5. 玻璃及自适应参数沿用原来的参数刷新方式。自适应开启时，基础色调强度不可调，请在自适应参数页调整明暗不透明度。光斑强度属于 Mango 全局设置，也会影响其他玻璃区域。

首次没有整合设置时默认启用四项。原来的参数不会重置。已有应急停用文件会使相应开关显示关闭；手动打开时面板会尝试清除该文件，失败会提示，避免显示已开而实际停用。

## 整合方式

- 四个原模块的已签名二进制保持原样，输入文件和模块 SHA-256 记录在 `inputs/sources.json` 及交付 manifest 中。没有以 1.2.1 源码替代 World 1.2.0，也没有以 AdaptiveColor 0.1.3.3 实验包替代 0.1.3。
- 一个新加载器在进程启动时读取独立域 `com.chenxun.mangosuite`，按总开关和四个子开关决定加载哪些模块。不会在运行中卸载已经挂钩的方法。
- AdaptiveColor 仅进入 backboardd；其余三项仅进入 SpringBoard。World 针对系统灵动岛窗口，Split 针对精确 UIWindow 类的 Mango 分屏窗口，保留原有作用范围。
- 原动态库放入 `Library/MangoSuite/Modules`，不保留它们的独立注入 plist。该目录的 `.jbroot → ../../..` 使原 RootHide 相对依赖仍能找到越狱根。
- 唯一顶层设置入口是 Mango 整合。玻璃页根据精确 Idle 参数页源码整理，自适应参数页使用原版 0.1.3 UI 二进制。

## 验证和限制

`tests/policy.c` 检查 512 种开关、应急标记和旧冲突状态在三个进程范围中的组合。`tests/check_suite.py` 对最终安装包检查四个原模块逐字节一致、arm64e ABI、签名代码页、唯一设置入口、RootHide 链接及包冲突声明。

新增 `tests/check_directories.py` 检查实际 DEB 的原始 tar 目录项与先后顺序。`tests/test_dpkg_install.py` 在 Linux 的隔离根目录内调用真实 dpkg，使用与交付包完全相同的 13 个载荷路径及权限、惰性文件内容，覆盖旧版缺目录错误、首次解包、失败后重试、升级保留设置四项。该测试验证安装包结构，不执行 iOS 动态库；不代表真机功能测试已完成。

编译和包结构验证不能代替真机测试。此版本标为 alpha2；交付时应以 `packages/verification.json` 和构建日志为准。尚需真机验证通知上划清除、灵动岛展开收拢、音乐活动切换、正反转向、分屏拖动和四个开关分别关闭后重新启动用户空间的效果。

## 回退

关闭总开关并重新启动用户空间可以停用四个整合模块。需要回到独立补丁时，先卸载 Mango 整合，再安装 `inputs/` 中四个原包并重新启动用户空间。原 Mango 参数不会在卸载时清空。

## 构建

macOS CI 只构建新的加载器及统一设置 bundle，使用 RootHide Theos、固定校验的 iOS 16.5 SDK 和 Xcode arm64e 工具链。原模块与本地最终包不上传构建分支。

下载构建 helper 后，在此目录执行：

```text
python tools/assemble.py --helper-deb <helper.deb>
python tests/check_suite.py packages/MangoSuite-1.0.0-alpha2-RootHide-arm64e.deb
```

`helper` 是中间构建产物，不是供设备安装的完整插件。请只安装最终 MangoSuite 包。
