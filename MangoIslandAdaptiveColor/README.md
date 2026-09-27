# MangoIslandAdaptiveColor 0.1.1 (实验版)

目标：让 Mango 的 `go.mangoos.island` 玻璃在空闲和活动状态下，按岛下方**实际背景像素的亮度**改变岛体的混色。它保留 MangoIdleIsland 1.1.5 已验证的边缘光与空闲态切换，不修改 Mango 原版文件。

## 实现范围

- 仅注入 `com.apple.backboardd`；安装后自动启用，无须手动创建启用文件。
- Mango 读取 `com.go.mangoosprefs` 的 Island 色调参数时，为 `Island.LightTintColor` 和 `Island.DarkTintColor` 提供临时标记。不会写回或覆盖用户设置。
- 仅对当前 Beta7-1 中出现的 Metal 源码做精确字符串校验；替换平面和曲面两处 `mix`。未带 Island 标记的其他玻璃仍执行原始混色。
- 暗背景给岛体少量亮色、亮背景增加暗色混合；保留 Mango 活动内容的白字可读性。无需取屏幕截图；像素由 Mango 原有渲染输入提供。
- 如果动态 Metal 编译失败，立即再用原始源码编译；日志记录原因。

这是未经真机验证的实验包。Mango 更新、偏好解析方式改变或初始化顺序不同都可能使它无效。`[SHADER]` 成功只能证明改过的源码完成编译，实际观感仍须用真机分别看空闲、音乐、通知等状态。

## 安装和恢复

安装 `.deb` 并重启用户空间后自动生效。插件在首次写日志时自动建立 `/var/mobile/Library/Logs/MangoIslandAdaptiveColor/` 文件夹和其中的 `Status.log`。查看 `[SHADER] ... compiled` 与 `[ISLAND] ... marker`。首次测试前保留 SSH 或 Dopamine 关闭 tweak 注入的入口。

如果显示异常、触摸异常或 backboardd 反复重启，重启设备后在 Dopamine 关闭 tweak 注入，再用 Sileo 卸载 `com.chenxun.mangoislandadaptivecolor`，然后正常越狱。原版 Mango、MangoIdleIsland 1.1.5 以及原有偏好未被修改。0.1.0 的 `.enable` 文件在本版无效，不影响运行。

## 构建

RootHide Theos、iOS 16.5 SDK：在此目录运行 `make package FINALPACKAGE=1`。CI 通过 `mango-island-adaptive-color.yml` 构建 `iphoneos-arm64e` 包。由于这里只能静态验证，还需要真机比较暗／亮背景下的空闲态、音乐活动态和通知活动态。
