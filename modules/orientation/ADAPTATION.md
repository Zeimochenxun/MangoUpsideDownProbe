# Beta9 方向模块适配

Suite 版本 `1.2.0~beta9.1`，目标 Mango `1.0-Beta9-1`、iOS 16.5、Dopamine RootHide、arm64e。适配依据是用户提供的安装包，SHA256 `4826d2e73c59f05e0ff529da1e7db47e494ebfc89498fd3c8280917268e2dadd`。

## 身份与 ABI

| 镜像 | Beta9 UUID |
|---|---|
| MangoHello.dylib | 2E847FEA-97B0-3739-9097-3CEDCC5E1D1A |
| MangoPanda.dylib | 2081DA7E-6C9B-30AA-9B3E-2DA9628A5B95 |
| MangoOSRendering.dylib | 7D067B62-6203-3D64-BE8A-3A4A7E965959 |

`Beta9Identity.h` 同时校验 Hello/Panda UUID，确认 pill、scene、floating 的声明镜像及关键 ABI。加载器还核对 Rendering 身份。未改写 Mango 文件、原生方向 getter 或授权。

已重新核对 Beta9：scene getter `q16@0:8` (0x57dbe4)，scene orientation-change `v28@0:8q16B24` (0x5e711c)，pill host `v24@0:8@16` (0xc4e034)，pill pan `v24@0:8@16` (0xc813a0)，launcher rotation/layout `v16@0:8` (0xb452ac/0xbc2d08)。小芒仍由 Panda 声明，controller `shouldAutorotate` 为 `B16@0:8`、`supportedInterfaceOrientations` 为 `Q16@0:8`。

Beta9 的 aperture resize-pan replacement 位于 0xca5338–0xca8adc，仍把方向1/2放在同一 portrait 分支，并在 Ended 阈值判断前读取原 translation.y，没有新增方向2的反转。World 因此保留现有窄范围补偿：只在 World 实际拥有该手势所在窗口的物理倒置时临时反转 y，返回或异常时恢复。

## 成品职责

World 编译 `World.m WorldPlacement.m XiaoMang.m`；Split 编译 `Split.m`。仅在校验过的原生类上挂钩，保留已有原生半转，不重复旋转；恢复也只针对当前仍匹配本插件写入的变换。

World 保留系统 aperture 窗口、content 和限定 container 的倒置与放置。Split 继续在 Mango scene/floating/launcher 回调后调和目标窗口。小芒按物理屏幕中心同时转换方向和位置，保持原生局部布局、手势和空白透传，范围见 [XIAOMANG.md](XIAOMANG.md)。

共享数学/helper 的部分 `MSB8*` 内部函数名表示继承的已测试策略，不代表它们仍使用 Beta8 镜像身份；全部运行时镜像调用已切为 `B9*`。

原生倒置偏好仍独立由整合设置页保存。Beta9 原版设置仍有将 `LeXiang.UpsideDown.Enabled` 写回 false 的路径；调整该值时使用整合页。

## 验证边界

本次 CI 执行生产数学、放置、手势、所有权、分屏首次施加回归及三项小芒 helper 测试，并重新编译 arm64e 产物。对应证据见交付目录 build-validation.json 和 package-verification.json。

Beta8 的历史媒体缺失及启动器偶发回正反馈继续列为真机验收项。本次没有连接手机验证实际显示、触摸和动画，测试通过不等于这些历史问题已经在 Beta9 解决。
