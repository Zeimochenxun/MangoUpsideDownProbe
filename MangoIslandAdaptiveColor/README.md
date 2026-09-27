# MangoIslandAdaptiveColor 0.1.6（渲染进程修复版）

目标：让 Mango 的 `go.mangoos.island` 玻璃在空闲和活动状态下形成连贯的一体化过渡，并按岛下方**实际背景像素的亮度**稳定改变岛体混色。它配合 MangoIdleIsland 1.1.8，不修改 Mango 原版文件。

## 实现范围

- 注入过滤直接匹配可执行文件 `SpringBoard`。实机 `Status.log` 与 `GlassProbe.log` 已确认 `MGLiveBackdropView` 和 `mangoos.dylib` 位于 SpringBoard；0.1.5 虽修正了过滤方式，但仍注入错误的 `backboardd`，因此无法接触真正的偏好读取与 Metal shader 编译。
- Mango 读取 `com.go.mangoosprefs` 的 Island 色调参数时，为 `Island.LightTintColor` 和 `Island.DarkTintColor` 提供临时标记。不会写回或覆盖用户设置。
- 仅对当前 Beta7-1 中出现的 Metal 源码做精确字符串校验；替换平面和曲面两处 `mix`。未带 Island 标记的其他玻璃仍执行原始混色。
- 保留用户在 `Island.LightTintColor` / `Island.DarkTintColor` 中设置的 alpha，并将完整 0–1 滑块映射到 0–42% 的安全混色范围；色调强度重新参与最终渲染，最大值仍至少保留 58% 背景。
- 新增独立的“自适应程度”参数：0 使用固定中性色调，1 使用完整亮度响应，中间值连续插值。参数量化为 15 级并编码在近黑／近白标记的低幅 RGB 变化中；即使 shader 回退，标记仍保持安全的近黑或近白颜色。
- 自适应色调使用更宽的 10%–85% 亮度响应区间：暗背景获得轻微提亮，亮背景混入近黑色。组合后的最终亮度仍保持单调，减少中灰拐点及动态背景闪烁。
- MangoIdleIsland 1.1.8 读取活动层的 presentation layer 透明度，以 60 fps 驱动空闲玻璃与活动玻璃的交叉过渡；空闲玻璃保持在同一 host 底层，不再在活动透明度刚超过 1% 时立即移除和重新插入。
- 如果动态 Metal 编译失败，立即再用原始源码编译；日志记录原因。
- 构造函数同时核对 `SpringBoard` 进程名和 bundle ID；修改后的 shader 编译失败时仍自动回退原始源码。

这是未经真机验证的实验包。Mango 更新、偏好解析方式改变或初始化顺序不同都可能使它无效。`[SHADER]` 成功只能证明改过的源码完成编译，实际观感仍须用真机分别看空闲、音乐、通知等状态。

## 安装和恢复

安装 `.deb` 并重启用户空间后自动生效。插件在 `SpringBoard` 执行构造函数并写日志时自动建立 `/var/mobile/Library/Logs/MangoIslandAdaptiveColor/` 文件夹和其中的 `Status.log`。查看 `[SESSION] 0.1.6 springboard-renderer`、`[SHADER] ... compiled` 与 `[ISLAND] ... marker`；若文件夹仍不存在，说明注入或日志写入路径仍需单独排查，不能据此断言颜色改动已经生效。首次测试前保留 SSH 或 Dopamine 关闭 tweak 注入的入口。

如果显示异常或 SpringBoard 反复重启，重启设备后在 Dopamine 关闭 tweak 注入，再用 Sileo 卸载 `com.chenxun.mangoislandadaptivecolor`，然后正常越狱。原版 Mango 以及原有偏好未被修改。0.1.0 的 `.enable` 文件在本版无效，不影响运行。

## 构建

RootHide Theos、iOS 16.5 SDK：在此目录运行 `make package FINALPACKAGE=1`。CI 通过 `mango-island-adaptive-color.yml` 构建 `iphoneos-arm64e` 包。由于这里只能静态验证，还需要真机比较暗／亮背景下的空闲态、音乐活动态和通知活动态。
