# 验证记录：0.1.0-alpha1

日期：2026-09-16。以下检查针对本次交付源码，不把历史 Probe 的绿色 Actions 当作 Fix 的构建结果。

## 已完成

- 使用宿主 GCC，`-std=c11 -Wall -Wextra -Werror` 编译并运行 `tests/geometry_test.c`：通过。
- 使用实际日志中的固定坐标样本，验证目标 minY≈736.652778、父坐标位移≈671.52：通过。
- 连续 10,000 次从已平移坐标反求基线并重算，数值不累积：通过。
- 不同展开高度、带缩放/旋转的父坐标、非零屏幕原点、保留原矩阵并撤销平移的算术测试：通过。
- NaN、零高、过大高度、奇异矩阵、已经位于屏幕下半部等拒绝条件：通过。
- **真实头文件检查**：libclang 18.1.1，`arm64e-apple-ios16.0` 目标，iPhoneOS16.5 SDK、Theos 官方 CydiaSubstrate framework header，Objective-C++ / ARC / blocks；`Tweak.xm` 语法和类型检查为 **0 个诊断**。这是解析检查，不是 Apple Clang 代码生成、链接、签名或真机 ABI 验证。
- plist 只注入 `com.apple.springboard`；7 个 hook 安装点限定在 Mango element 和真实 aperture 容器类；无全局 UIView hook：检查通过。
- 原方法调用点保持一次；没有增加旋转、删除系统动画、修改原始二进制或写入 Mango 配置：源码检查通过。
- GitHub workflow YAML 和内嵌 shell 语法：检查通过。
- `tools/check_package.py` 的 Python 语法检查通过，实际输入历史 Probe deb 被正确拒绝为错误包名。
- 原始 `mango.dylib` 与 `MangoOSRendering.dylib` SHA-256 与初始分析值一致。

SDK 文件来自 Theos 固定 release：

```text
https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz
SHA256: 5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb
```

SDK 与 Substrate 头文件仅用于本地检查，不包含在交付包中。测试使用的 `Geometry.h` 就是生产源码引用的同一文件，未用另写的算法代替。

## 构建后自动检查

附带 Actions 工作流使用 macOS 和 RootHide Theos。除编译外，还会运行几何测试，拒绝 `incompatible arm64e ABI` 警告，并检查生成 deb 的：

- 包 ID、`iphoneos-arm64e` 包架构。
- payload 恰好包含 Fix 的 dylib/plist；不包含 Mango 原文件。
- SpringBoard 专用过滤器。
- thin arm64e Mach-O dylib 标记。
- RootHide `.jbroot` rpath、无硬编码 `/var/jb` 动态库依赖。
- 存在嵌入签名数据；此检查不等于设备信任或完整密码学验证。

工作流记录编译器版本、Theos commit、源码与 SDK 哈希，便于把后续日志与确切产物关联。

## 尚未完成

- **本次 Fix 尚未运行 GitHub Actions/macOS 编译，没有交付已编译 `.deb`。**
- 尝试通过现有 GitHub 连接读取交接包所指私有仓库的 Makefile，返回 404；未改写远程仓库、未提交或启动工作流。该响应不能区分权限不足与仓库已变更。
- 未在 iPhone 上安装 Fix。
- 未验证 UIKit 实际 setter 嵌套顺序、系统父布局如何读取已平移 frame，以及 Objective-C runtime hook 的真机行为。
- 未验证展开/收起的 presentation layer 动画、系统触摸区域、自定义 hit testing、safe area 效果。
- 未验证全部音乐、计时器、通知及 Live Activity 容器。
- 未在设备上实测禁用标记和恢复动作；恢复方案已提供，不能把恢复代码存在当作已演练。

最终交付状态：**完成一版受限实验性实现与本地检查，可进入 macOS 构建和可恢复的真机测试；尚未达到稳定修复的验证标准。**
