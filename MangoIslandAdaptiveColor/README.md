# MangoIslandAdaptiveColor 0.1.2.2

以真机基本可用的 0.1.2 为视觉基线，把 Mango `go.mangoos.island` 的背景自适应混色拆成可调参数，并彻底移除 0.1.2.1 的 Settings 预览 / 自定义 Cell。

## 默认值 = 0.1.2

- 总自适应强度：1.00
- 响应起点：0.08
- 响应终点：0.42
- 暗背景目标亮度：0.80
- 亮背景目标亮度：0.025
- 暗区混合强度：0.16
- 亮区混合强度：0.42

以上默认组合在 shader 中仍等价于：

```text
bright = smoothstep(0.08, 0.42, luminance)
target = mix(0.80, 0.025, bright)
opacity = mix(0.16, 0.42, bright)
out = mix(background, target, opacity)
```

默认参数还会重新编码为 0.1.2 原始 Island markers：`#FEFEFD1A` / `#0101021A`。

## 可调项目

设置页仅使用系统原生 Preferences 控件，不再包含 `MIAAdaptivePreviewView`、`MIAAdaptivePreviewCell` 或 `cellClass`。

可调参数：总强度、亮度响应起点/终点、暗/亮背景目标亮度、暗/亮端混合强度。每个参数在实时 marker transport 中量化为 8 个稳定档位；滑块写入后通过 `com.go.mangoosprefs/Reload` 合并刷新，不需要每次重新编译 Metal shader。

## 实现边界

- 仅注入 `com.apple.backboardd`。
- 不修改 Mango 原始二进制文件。
- 仍只替换 Beta7-1 已验证的两处 Metal tint mix；其他 Mango 玻璃沿用原始路径。
- Island 参数由两个临时 tint marker 传输，不写回 `Island.LightTintColor` / `Island.DarkTintColor`。
- Metal 修改失败时回退原始 shader。

## 构建

RootHide Theos + iOS 16.5 SDK：`make package FINALPACKAGE=1`。CI 同时检查 arm64e tweak、PreferenceBundle、PreferenceLoader 入口、0.1.2.2 版本、参数键，并强制确认最终设置 Bundle 不含旧预览类字符串。
