# MangoIslandAdaptiveColor 0.1.8（双进程渲染修复版）

目标：让 Mango 的 `go.mangoos.island` 玻璃在空闲和活动状态下形成连贯的一体化过渡，并按岛下方**实际背景像素的亮度**稳定改变岛体混色。它配合 MangoIdleIsland 1.1.8，不修改 Mango 原版文件。

## 实现范围

- 同时注入 `SpringBoard` 与 `backboardd`。实机日志确认 `MGLiveBackdropView` / `mangoos.dylib` 的视图层位于 SpringBoard；原版 `MangoOSRendering.plist` 和可工作的 0.1.2 包则共同证明实际 Metal backdrop renderer 位于 backboardd。0.1.6–0.1.7 只注入 SpringBoard，因此只能产生 Light/Dark 模式色，无法修改实际背景采样 shader。
- 0.1.6 的 Island 标记要求近黑／近白颜色分量几乎逐位相等；UIColor 到 Metal uniform 之间一旦发生 alpha 预乘或 sRGB 线性化，标记就会失配并退回 Mango 原生 Light/Dark 混色。0.1.7 同时比较原值、反预乘值、线性值和反预乘线性值，仍用偏移的 G/B 签名排除普通纯黑与纯白。
- Mango 读取 `com.go.mangoosprefs` 的 Island 色调参数时，为 `Island.LightTintColor` 和 `Island.DarkTintColor` 提供临时标记。不会写回或覆盖用户设置。
- 仅对当前 Beta7-1 中出现的 Metal 源码做精确字符串校验；替换平面和曲面两处 `mix`。未带 Island 标记的其他玻璃仍执行原始混色。
- 保留用户在 `Island.LightTintColor` / `Island.DarkTintColor` 中设置的 alpha，并把完整 0–1 滑块映射为从原始 backdrop 到完整自适应结果的连续强度。
- 新增独立的“自适应程度”参数：0 使用固定中性色调，1 使用完整亮度响应，中间值连续插值。参数量化为 15 级并编码在近黑／近白标记的低幅 RGB 变化中；即使 shader 回退，标记仍保持安全的近黑或近白颜色。
- 自适应色调沿用 0.1.2 在纯黑／纯白背景上的输出端点，但改用 8%–85% 的单调连续映射；暗背景提亮、亮背景压暗，同时消除 0.1.2 中间亮度区间的反向拐点。
- MangoIdleIsland 1.1.8 读取活动层的 presentation layer 透明度，以 60 fps 驱动空闲玻璃与活动玻璃的交叉过渡；空闲玻璃保持在同一 host 底层，不再在活动透明度刚超过 1% 时立即移除和重新插入。
- 如果动态 Metal 编译失败，立即再用原始源码编译；日志记录原因。
- 构造函数分别识别 SpringBoard 视图侧与 backboardd renderer；修改后的 shader 编译失败时仍自动回退原始源码。

这是未经真机验证的实验包。Mango 更新、偏好解析方式改变或初始化顺序不同都可能使它无效。`[SHADER]` 成功只能证明改过的源码完成编译，实际观感仍须用真机分别看空闲、音乐、通知等状态。

## 安装和恢复

安装 `.deb` 并重启用户空间后自动生效。插件自动建立 `/var/mobile/Library/Logs/MangoIslandAdaptiveColor/Status.log`。查看 `[SESSION] 0.1.8 dual-process role=view`、`role=renderer`、`[SHADER] ... marker-decoder=raw+unpremultiplied+linear` 与 `[ISLAND] ... marker`。其中 `role=renderer` 和 `[SHADER]` 是屏幕背景自适应真正工作的关键。首次测试前保留 SSH 或 Dopamine 关闭 tweak 注入的入口。

如果显示异常、SpringBoard 或 backboardd 反复重启，重启设备后在 Dopamine 关闭 tweak 注入，再用 Sileo 卸载 `com.chenxun.mangoislandadaptivecolor`，然后正常越狱。原版 Mango 以及原有偏好未被修改。0.1.0 的 `.enable` 文件在本版无效，不影响运行。

## 构建

RootHide Theos、iOS 16.5 SDK：在此目录运行 `make package FINALPACKAGE=1`。CI 通过 `mango-island-adaptive-color.yml` 构建 `iphoneos-arm64e` 包。由于这里只能静态验证，还需要真机比较暗／亮背景下的空闲态、音乐活动态和通知活动态。
