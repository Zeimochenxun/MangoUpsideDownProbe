# MangoIslandAdaptiveColor 0.1.3（动画连贯性实验版）

目标：让 Mango 的 `go.mangoos.island` 玻璃在空闲和活动状态下形成连贯的一体化过渡，并按岛下方**实际背景像素的亮度**稳定改变岛体混色。它配合 MangoIdleIsland 1.1.6，不修改 Mango 原版文件。

## 实现范围

- 仅注入 `com.apple.backboardd`；安装后自动启用，无须手动创建启用文件。
- Mango 读取 `com.go.mangoosprefs` 的 Island 色调参数时，为 `Island.LightTintColor` 和 `Island.DarkTintColor` 提供临时标记。不会写回或覆盖用户设置。
- 仅对当前 Beta7-1 中出现的 Metal 源码做精确字符串校验；替换平面和曲面两处 `mix`。未带 Island 标记的其他玻璃仍执行原始混色。
- 色调输出改成全区间单调曲线：暗背景只做克制提亮，亮背景柔和压暗，中灰区不再出现背景越亮、岛体反而突然变暗的拐点。输出保留 62% 的背景颜色，压缩快速滚动、视频和细纹理带来的亮度扰动。
- MangoIdleIsland 1.1.6 读取活动层的 presentation layer 透明度，以 60 fps 驱动空闲玻璃与活动玻璃的交叉过渡；空闲玻璃保持在同一 host 底层，不再在活动透明度刚超过 1% 时立即移除和重新插入。
- 如果动态 Metal 编译失败，立即再用原始源码编译；日志记录原因。
- 延续 0.1.2 的 `backboardd` 进程识别和低 alpha 临时标记；修改后的 shader 编译失败时仍自动回退原始源码。

这是未经真机验证的实验包。Mango 更新、偏好解析方式改变或初始化顺序不同都可能使它无效。`[SHADER]` 成功只能证明改过的源码完成编译，实际观感仍须用真机分别看空闲、音乐、通知等状态。

## 安装和恢复

安装 `.deb` 并重启用户空间后自动生效。插件在 `backboardd` 执行构造函数并写日志时自动建立 `/var/mobile/Library/Logs/MangoIslandAdaptiveColor/` 文件夹和其中的 `Status.log`。查看 `[SESSION]`、`[SHADER] ... compiled` 与 `[ISLAND] ... marker`；若文件夹仍不存在，说明注入或日志写入路径仍需单独排查，不能据此断言颜色改动已经生效。首次测试前保留 SSH 或 Dopamine 关闭 tweak 注入的入口。

如果显示异常、触摸异常或 backboardd 反复重启，重启设备后在 Dopamine 关闭 tweak 注入，再用 Sileo 卸载 `com.chenxun.mangoislandadaptivecolor`，然后正常越狱。原版 Mango 以及原有偏好未被修改。0.1.0 的 `.enable` 文件在本版无效，不影响运行。

## 构建

RootHide Theos、iOS 16.5 SDK：在此目录运行 `make package FINALPACKAGE=1`。CI 通过 `mango-island-adaptive-color.yml` 构建 `iphoneos-arm64e` 包。由于这里只能静态验证，还需要真机比较暗／亮背景下的空闲态、音乐活动态和通知活动态。

