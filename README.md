# 双层 Dock

iOS 16（RootHide，arm64e）的 SpringBoard 插件。在 iPad 样式的悬浮 Dock 上往上滑，拉出第二排 App；往下滑收起。

这个抽屉原来是 Mango Suite 的一部分（1.2.0~beta9.9.15–9.9.24，已在 iPhone 13 mini / iOS 16.5 上调好），这里拆出来单独成包，并自带 iPad 样式 Dock 的开关，不再需要 Lynx。

## 设置（设置 → 双层 Dock）

- **启用双层 Dock**：默认开，改动立刻生效。
- **固定 App 后加分隔线**：默认开。
- **第二排固定 App**：最多 5 个，排在第二排最左边，右边放最近使用。固定的 App 不会出现在第一排的最近使用里。
- **启用 iPad 样式 Dock**：默认开。效果和 Lynx 的“浮动 Dock”一样，都是让 `+[SBFloatingDockController isFloatingDockSupported]` 返回 YES。注销后生效。Lynx 里也开着时两边不冲突。
- **倒置时 Dock 避开刘海** / **Dock 抬升高度**：默认开、35 点（iPhone 13 mini 刘海 5.35mm 折合），0–50 可调。屏幕倒过来时 Dock 的底边在刘海下面，打开后完全出来的 Dock 会再往上抬这么多，滑动距离不变；正着用时不受影响。改动立刻生效。
- **刘海处防误触**：默认开。倒置时回主屏手势的底边识别区保持至少 50 点；前台是 App 时，刘海正下方（中心 ±95 点、离边 48 点内）放一条几乎透明的 SpringBoard 挡条，从这里开始的上划只交给系统（回主屏、唤出 Dock），不再误点到 App。代价是这一窄条里的点按也不会传给 App。正着用、主屏幕上不受影响。改动约 0.25 秒内生效。
- **导出诊断日志**：日志在 `/var/mobile/Library/Application Support/DoubleDock/`（RootHide 下位于 jbroot 内）。

第一次运行会沿用 Mango Suite 里的固定 App、分隔线、“倒置时 Dock 避开刘海”（同时用于抬升和防误触两个开关）和抬升高度，以及最近使用列表。

是否倒置：抬升看 Dock 所在窗口相对屏幕的方向，防误触的底边识别区看回主屏手势自己的触摸方向，挡条看系统状态栏方向。都不读 Mango 的内部接口。

## 与其他插件

- **Lynx**：浮动 Dock 两边谁开都行。第一排的运行标记来自 Lynx，第二排照抄它的样子；Lynx 不显示标记时，第二排也不显示。
- **Mango Suite**：Suite 自带的“双层 Dock”开着时，本插件的第二排自动让开，设置页顶部会提示。请在 Suite 里关掉，再注销一次。
- **倒置抬升和防误触**：Suite 的“倒置时 Dock 避开刘海”开着时，这两项都由 Suite 做，本插件自动让开，不会抬两次、也不会叠两条挡条；Suite 里关掉或不装 Suite 时由本插件做。独立版 World 1.3.0 装着时，抬升和底边识别区交给它，挡条（它没有）由本插件放。

## 构建

本机没有 Theos，构建走 GitHub Actions（`.github/workflows/build.yml`，macOS 上用 RootHide Theos 和 iOS 16.5 SDK）：

```
python -I tools/gh.py publish
python -I tools/gh.py status
python -I tools/gh.py download --run <id>
```

`tests/check.m` 是抽屉数学和设置文件的检查，在 CI 上先于打包运行。
