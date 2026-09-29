# MangoIslandAdaptiveColor 0.1.3

本版优先修复 0.1.2.2 的作用域问题：其它 Mango 玻璃如果使用相似 tint，不应再被误识别为灵动岛。新的 renderer 只有在 tint 同时满足 Island marker 编码、checksum 和参数合法性校验时，才进入自适应分支；其它玻璃保持 Mango 原始 tint mix。

## 新默认参数

- 总自适应强度：0.90
- 响应起点：0.08
- 响应终点：0.52
- 暗背景目标亮度：0.80
- 亮背景目标亮度：0.08
- 暗区混合强度：0.16
- 亮区混合强度：0.20

相比 0.1.2，亮背景默认混合明显降低，普通亮度过渡拉长，优先保留玻璃下方的真实颜色和细节。

## Highlight Glass

当背景亮度进入高亮区间（约 0.68–0.92）时，算法从普通灰度目标混合逐步切换到保留 RGB 比例的亮度压缩：

- 降低灰膜感；
- 保留背景色彩和纹理；
- 在高亮背景下增强 Island 的色散强度；
- 增加一层轻微暗 Fresnel rim，补偿白色边缘光在白背景下不可见的问题；
- 同时降低高亮背景下白色 Fresnel glare 的增益，避免边缘进一步泛白。

这些补偿只在通过 Island marker 校验时启用。

## Island-only marker

0.1.2.2 仅通过 RGB 高/低半区 + 固定 alpha 判断 marker，范围过宽，理论上会与其它玻璃 tint 发生碰撞。0.1.3 改为：

1. 仍只替换 `Island.LightTintColor` / `Island.DarkTintColor` 的读取结果；
2. 21-bit 配置继续编码在 RGB；
3. alpha 改为由 packed configuration 计算出的低透明度 checksum；
4. shader 解码后再次验证亮度区间与目标亮度组合是否合法；
5. 任一条件不满足，立即执行 Mango 原始 `mix(background, tint.rgb, tint.a)`。

## 设置

设置页只使用系统原生 Preferences 控件，无预览和自定义 Cell。保留 7 项可调参数，并新增“恢复默认参数”按钮，一键恢复本版推荐值。

## 构建

RootHide Theos + iOS 16.5 SDK：`make package FINALPACKAGE=1`。CI 检查 arm64e tweak、PreferenceBundle、PreferenceLoader、0.1.3 版本、Island-only checksum、Highlight Glass 字符串、恢复默认参数按钮，并确认旧预览类未进入最终 Bundle。
