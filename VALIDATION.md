# 验证记录：0.2.0-alpha2

日期：2026-09-16（alpha1）／本次 alpha2 修改。下面按"这一版实际做过什么"记录，不把 alpha1 的检查结果当作 alpha2 的检查结果。

## alpha2 本次改动的验证状态

**先说结论：alpha2 的代码尚未经过任何编译器检查。** 本次改动在没有 C/Objective-C 工具链的环境中完成，`clang`、`gcc` 均不可用，因此：

- **未编译 `Tweak.xm`**。alpha1 做过的 libclang 解析检查，这一版**没有**重做。
- **未运行 `tests/geometry_test.c`**（本机无 C 编译器）。但 **`Geometry.h` 在 alpha2 中逐字节未改**，所以 alpha1 对坐标算法的测试结论仍然适用于生产代码；CI 会在构建时重新运行该测试。
- **未在设备上安装或测试 alpha2。**

因此提交后**必须先跑 GitHub Actions**，绿色之后再安装。首次编译很可能需要修正编译错误——请把编译日志作为下一步输入，不要绕过它直接装。

已完成的源码级检查（人工阅读，非工具验证）：

- 坐标算法未改动：`Geometry.h` 与 alpha1 相同。
- 注入面未扩大：plist 仍只注入 `com.apple.springboard`。
- 新增 4 个 hook 全部落在已证据化的 aperture 容器类与 aperture 窗口类上，安装前检查方法签名；**没有新增全局 UIView/UIWindow hook，没有挂钩 `SBFTouchPassThroughView`**。
- 4 个探针 hook 均先调用原实现、记录后**原值返回**；没有任何分支修改返回值或事件分发。
- 探针的祖先查询会重入被挂钩的 `pointInside:`，已加重入标记抑制嵌套记录。
- 待挂载队列使用弱引用、去重、上限 64、TTL 30 秒；复查遍历快照并按对象标识移除，带重入保护（关联会触发布局，布局可能再次进入 Mango 回调）。
- 禁用标记生效时清空队列并停止探针记录。
- 新增 `.noprobe` 标记可单独关闭探针而保留位移修复。

## alpha1 已完成的检查（仍然有效的部分）

- 使用宿主 GCC，`-std=c11 -Wall -Wextra -Werror` 编译并运行 `tests/geometry_test.c`：通过。
- 使用实际日志中的固定坐标样本，验证目标 minY≈736.652778、父坐标位移≈671.52：通过。
- 连续 10,000 次从已平移坐标反求基线并重算，数值不累积：通过。
- 不同展开高度、带缩放/旋转的父坐标、非零屏幕原点、保留原矩阵并撤销平移的算术测试：通过。
- NaN、零高、过大高度、奇异矩阵、已经位于屏幕下半部等拒绝条件：通过。
- **真实头文件检查**：libclang 18.1.1，`arm64e-apple-ios16.0` 目标，iPhoneOS16.5 SDK、Theos 官方 CydiaSubstrate framework header，Objective-C++ / ARC / blocks；**alpha1 的** `Tweak.xm` 语法和类型检查为 0 个诊断。这是解析检查，不是代码生成、链接、签名或真机 ABI 验证，**且不覆盖 alpha2 的改动**。
- 原方法调用点保持一次；没有增加旋转、删除系统动画、修改原始二进制或写入 Mango 配置：源码检查通过（alpha2 维持同样纪律）。
- GitHub workflow YAML 和内嵌 shell 语法：检查通过。
- `tools/check_package.py` 的 Python 语法检查通过，实际输入历史 Probe deb 被正确拒绝为错误包名。
- 原始 `mango.dylib` 与 `MangoOSRendering.dylib` SHA-256 与初始分析值一致。

## alpha1 真机测试结果

这是 alpha2 存在的原因，记录在此以免丢失：

- **成功**：倒置时展开态灵动岛移动到了正确的视觉位置，容器从上方移到了下方镜像位置。
- **失败 1**：触摸行为不正确。视觉位置变了，命中测试/手势路由仍按原坐标。
- **失败 2**：紧凑态小岛与媒体小岛完全没有移动，原因是其 host 在 Mango 回调时 `window == nil`，被 alpha1 丢弃。

alpha2 针对失败 2 做了修复（排队复查），针对失败 1 只做了诊断（只读探针）。

SDK 文件来自 Theos 固定 release：

```text
https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz
SHA256: 5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb
```

## 构建后自动检查

附带 Actions 工作流使用 macOS 和 RootHide Theos。除编译外，还会运行几何测试，拒绝 `incompatible arm64e ABI` 警告，并检查生成 deb 的：

- 包 ID、`iphoneos-arm64e` 包架构。
- payload 恰好包含 Fix 的 dylib/plist；不包含 Mango 原文件。
- SpringBoard 专用过滤器。
- thin arm64e Mach-O dylib 标记。
- RootHide `.jbroot` linkage、无硬编码 `/var/jb` 动态库依赖。
- 存在嵌入签名数据；此检查不等于设备信任或完整密码学验证。

工作流记录编译器版本、Theos commit、源码与 SDK 哈希，便于把后续日志与确切产物关联。

## 尚未完成

- **alpha2 尚未编译，没有 `.deb`，也未在 iPhone 上安装。**
- 未验证排队复查在真机上是否真的能捕获紧凑态/媒体小岛的 host——这正是第 7 步测试要回答的问题。
- 未验证探针输出能否定位触摸失败的原因；探针本身未在真机运行过。
- 未验证 UIKit 实际 setter 嵌套顺序、系统父布局如何读取已平移 frame，以及 Objective-C runtime hook 的真机行为。
- 未验证展开/收起的 presentation layer 动画、系统触摸区域、自定义 hit testing、safe area 效果。
- 未验证全部音乐、计时器、通知及 Live Activity 容器。
- 未在设备上实测禁用标记和恢复动作；恢复方案已提供，不能把恢复代码存在当作已演练。

最终交付状态：**alpha2 是一版未编译的源码改动，覆盖 alpha1 真机暴露的两个问题中的一个（紧凑态生命周期），另一个（触摸）只加了取证手段。下一步是 CI 编译，然后按 README 第 7、8 步取日志。**
