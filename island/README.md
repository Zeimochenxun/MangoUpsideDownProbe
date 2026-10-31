# 灵动岛 0.2.0（实验，未上机）

从 Mango 的「灵动岛模拟」里提取出来的独立插件：让带刘海的 iPhone（目标是 iPhone 13 mini，iOS 16.5，Dopamine RootHide，arm64e）用上系统自己的灵动岛，带 Mango 那 10 个分辨率预设，并且能调灵动岛的大小和位置；调节写在不会碰倒置的那一层，倒置时不会失效。不装 Mango 也能用，不读、不改、不依赖 Mango 的任何文件。

标记沿用之前的约定：**【读】** 在二进制或日志里看到过，**【推】** 由读到的东西推出来，**【缺】** 还没在真机上见过。这个版本的所有运行效果都是【缺】；下面写的是 Mango 做法的依据、对应关系和上机时怎么看结果。Mango 那边每一项的依据（方法、流程、弹窗原文、预设表）见 [MANGO-SIMULATION.md](MANGO-SIMULATION.md)。

## 和 Mango 灵动岛模拟的对应

Mango 菜单里「灵动岛」一栏的末尾是模拟（类 `MangoDynamicIslandSimulation`，14 个类方法，Beta9 与 Beta12 逐项相同）：模式、应用/取消、分辨率预设、应用/恢复分辨率。位置与缩放在 Mango 的设置页里。下表是这些功能在本插件里的位置。

| Mango 的功能 | Mango 的做法【读】 | 本插件 | 状态 |
|---|---|---|---|
| 模拟灵动岛模式 | 两档：`Pro (1179×2556)`、`Pro Max (1290×2796)`；`enableWithMode:` 0 写 2556，其余写 2796 | 「模式」，同样两档同样两个值 | 已做 |
| 应用模拟灵动岛 | 改 `MobileGestalt.plist` 的 `CacheExtra["oPeik/9e8lQWMszEjbPzng"]`，XML 原子写，随后注销 | 「应用模拟灵动岛」，同一个键同一个文件，在 SpringBoard 里做；先备份原缓存和原值 | 已做，比 Mango 多备份 |
| 取消模拟 | `disable` 写回 `defaultDeviceSubType`，它就是 `(NSInteger)UIScreen.nativeBounds.size.height`（`nativeBounds` 之后一条 `fcvtzs d3`，没有查表） | 「取消模拟」，写回备份的原值；没有备份就按同一条规则用 `nativeBounds` 高度 | 已做 |
| 是否已模拟 | `isCurrentlyEnabled`：当前值是 2556 或 2796，且不等于 `nativeBounds` 高度（用真实控制流逐组合验证过） | 设置页文字里的「已模拟 / 未模拟」，同一条规则；本机自带灵动岛（原生高度 2556/2796）时直接说不需要，什么都不改 | 已做 |
| iOS 16.1 闸 | 低于 16.1 弹「系统版本不支持」，应用模拟和应用分辨率都拦 | 应用模拟、应用分辨率都拦，提示的意思相同；取消、恢复不拦 | 已做 |
| 确认弹窗 | `⚠️ 模拟灵动岛`「即将切换至 %@ 模式 … 此操作会修改系统配置文件，请在充分了解风险后使用」；`⚠️ 取消模拟灵动岛`「即将恢复为原始设备子类型 (%ld)」 | 标题和主体的意思相同，加了备份与还原文件的说明 | 已做 |
| 分辨率预设 | 10 项：iPhone 16 Pro Max 1320×2868、iPhone 16 Pro 1206×2622、15ProMax / 14ProMax 1290×2796、15Pro / 14Pro (灵动岛) 1179×2556、13ProMax / 12ProMax 1284×2778、13Pro / 12Pro 1170×2532、13mini / 12mini 1080×2340、XS / X 1125×2436、iPad Pro 12.9" 2048×2732、iPad Pro 11" 1668×2388；菜单项格式 `%@ — %ld×%ld` | 「预设」，同样 10 项同样顺序同样标签（`tests/island_test.c` 逐项核对） | 已做 |
| 应用分辨率 | 删 `/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist`；写入 `{canvas_height, canvas_width}`（整数，`writeToURL:atomically:YES`）；删 `/private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist` 并建指向前者的符号链接；0.5 秒后注销。弹窗`⚠️ 应用分辨率`显示预设与「当前原生」尺寸，带「恢复默认分辨率」 | 「应用分辨率」，同样的文件、键、链接、弹窗（三个按钮齐）；Preferences 那个位置上若已有别的文件或链接，先留一份再放回；写完经链接读回核对 | 已做 |
| 恢复默认分辨率 | 把上面两个路径都删掉，0.5 秒后注销 | 「恢复默认分辨率」：只删指向画布文件的链接和画布文件，不动别人放在那里的东西，被顶替的原文件放回去 | 已做 |
| 当前原生分辨率 | `nativeResolution`（实时读 `nativeBounds` 的尺寸） | 分辨率一栏的说明文字，显示的是面板自己的尺寸（见下「面板尺寸」），系统此刻报告的屏幕尺寸不同时另外注明 | 已做 |
| 注销 | `performUserSpaceReboot` 发 Darwin 通知 `com.go.mango.respring`，SpringBoard 里的观察者调 `[FBSystemService exitAndRelaunch:YES]` | 本插件就在 SpringBoard 里，直接调 `exitAndRelaunch:YES`，不经通知 | 已做 |
| 灵动岛位置与缩放 | `PillGlass.PosAdjust/PosX/PosY/PosScale`：把 anchorPoint 设成 (0.5, 42/视图高度)，`CGAffineTransformMakeScale` 缩放，位置用 `setCenter:` 平移 | 「大小与位置」：写一个 transform 在中间一层透传视图上（见下），缩放中心取 Mango 同款的「节点顶端往下 42 点、水平居中」 | 已做，写法不同（为了不碰倒置） |

比 Mango 多出来的（都是为了能退回去）：第一次模拟前备份整个缓存文件和原机型值；崩溃保护；`DynamicIsland.restore` 还原文件；画布只删自己的东西、顶替掉的文件留底。

### 灵动岛一栏里没有做的

这些不属于 `MangoDynamicIslandSimulation`，是 Mango 在同一栏或设置页里的其它灵动岛功能，各自是独立的大块，这一版没有做：

| 功能 | 为什么没做 |
|---|---|
| 消息岛（通知胶囊）：多岛共存、前台退岛动画、岛消失延迟、岛点击行为、岛下拉/上滑手势、岛宽度压缩、模拟通知（`MangoPillElement` / `MangoPillManager`，是真正的灵动岛元素，要截住通知横幅再交给自己的元素） | 要挂 SpringBoard 的通知横幅、注册系统灵动岛元素，用到的私有类和协议在 iOS 16.5 上的样子还没有拿到，不上机没法验证；做错会让 SpringBoard 崩 |
| 灵动岛液态玻璃、仅展开显示、兼容模式、黑色光晕（形状/透明度/范围） | 玻璃是 backboardd 里挂 QuartzCore 的渲染器（`MangoOSRendering`），iOS 16.5 一侧的 QuartzCore 函数和结构还没分析，挂错会开机循环 |
| 灵动岛音量滑条、锁屏音量滑条 | 依赖上面的玻璃和 Mango 的音量 HUD 替换 |
| 灵动岛分屏快捷行 | 依赖 Mango 自己的分屏功能 |
| 自绘频谱（音频跳动、专辑图脉冲、专辑颜色自适应、5 种样式） | 频谱的音频电平从哪里来没有读到 |

## 它做三件事

### 1. 机型模拟（Disguise.m）

SpringBoard 靠 MobileGestalt 里的 `ArtworkDeviceSubType` 判断要不要建灵动岛。改成 2556（14 Pro）或 2796（14 Pro Max），注销后系统自己的灵动岛就出现了。

- 【读】Mango 改 `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist` 里 `CacheExtra["oPeik/9e8lQWMszEjbPzng"]`，读时用可变容器，写回 XML，原子替换，不 chmod，然后 `[FBSystemService exitAndRelaunch:YES]`。本插件做法相同，也在 SpringBoard 里做：设置页只发请求（`request.plist` + Darwin 通知），SpringBoard 执行并回写 `result.plist`。
- 【读】机型值的「原值」就是面板的像素高：Mango 的 `defaultDeviceSubType` 只做 `UIScreen.mainScreen.nativeBounds.size.height` 取整。**13 mini 的面板是 1080×2340，所以这条规则给出 2340**【推：`nativeBounds` 的值没在这台机器上见过】；0.1.0 的说明里写成 2436 是错的。代码一直是运行时读 `nativeBounds`，行为没受影响，只是说明和测试注释写错了。日志 `INSTALLED` 行的 `nativeHeight=` 会给出这台机器的真值。
- 比 Mango 多出来的：
  - 第一次模拟前把整个缓存文件和原机型值备份到 `…/Application Support/DynamicIsland/`（`MobileGestalt.original.plist`、`original.plist`）。如果当前值已经是 2556/2796（比如之前用 Mango 模拟过），不会把它当成「原值」备份，取消时按 `nativeBounds` 推算。
  - 【崩溃保护】模拟后 SpringBoard 第一次重启就在 15 秒内死掉，下一次启动时插件会先把机型值写回去；活过 60 秒就解除保护。保护只撤销**被它盯着的那一项**（机型、画布或两者），不会因为刚改了分辨率就顺带撤掉稳定用了几天的机型模拟。
  - 【还原文件】在 `/var/mobile/Library/Preferences/` 新建一个空文件 `DynamicIsland.restore`（Filza 或 ssh），插件下次启动或 5 秒内就把机型值和画布都还原并注销。
- 本机自带灵动岛（原生像素高 2556/2796）时直接拒绝，什么都不改。
- **面板尺寸**【推】：画布生效时，`UIScreen.nativeBounds` 很可能报告画布的尺寸（这正是改画布的目的），而 Mango 的 `defaultDeviceSubType` 是实时读它的：在 14 Pro 尺寸（1179×2556）的画布下，它会把 13 mini 当成「已经有灵动岛」，取消模拟时也会写回 2556。本插件在没有画布的时候把面板自己的尺寸记在 `panel.plist`（SpringBoard 每次启动、以及应用画布前都会记），画布生效期间关于机型值的所有判断（自带灵动岛、已模拟、取消时写回什么）都用这个记下的值，所以「Pro 样式 + 14 Pro 画布」先后顺序随便。画布是别的东西（比如 Mango）先设上、插件没记过面板尺寸时，只能用实时值。`nativeBounds` 在画布下到底报告什么是【缺】，日志 `INSTALLED` 行的 `nativeHeight=`（面板）和 `live=`（系统此刻报告的）会给出答案。

### 2. 分辨率（Canvas.m）

照 Mango 的「应用分辨率」：写 `/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist`，里面 `canvas_width`、`canvas_height` 两个整数；在 `/private/var/mobile/Library/Preferences/` 里同名位置放一个指向它的符号链接；注销。

- 【读】路径、键、链接、0.5 秒后注销都是从 Mango 的 `applyResolutionWithWidth:height:` 在真实控制流上跑出来的。
- 【缺】iOS 16.5 上系统认不认这两个键，只有上机才知道。Mango 的弹窗自己也写着「如果出现黑屏/花屏等异常，请重新注销恢复」。
- 设置页只传预设的序号，插件自己查表，并再检查一遍尺寸合理（每边 640–4096）。
- 应用时先看 Preferences 那个位置：没东西就直接建；已经是指向画布文件的链接（本插件上次留下的，或 Mango 留下的，路径相同）就只重写画布文件；是别人的普通文件或指向别处的链接就先复制一份到 `IOMobileGraphicsFamily.foreign.plist` 再换成我们的链接；是目录之类的就拒绝。写完经链接读回，尺寸不对就撤回。
- 恢复时只删指向画布文件的链接和画布文件，被顶替的东西放回去（位置是空的才放）；那个位置上现在是别人的东西就不动它。
- 崩溃保护和还原文件对画布同样有效。

### 3. 大小和位置（Tweak.m）

设置页里的「大小」「左右」「上下」。方向按你看到的算：向右、向下为正，正着拿、倒置时都一样，**倒置时不需要另外设置**。

## 为什么调节不会再让倒置失效

之前的故障，从仓库里的代码和证据能读出来：

- 【读】灵动岛窗口 `SBSystemApertureWindow` 本身带 25/24 的缩放；里面是三层 `SBFTouchPassThroughView`（identity），再往里是 `SBSystemApertureContainerView` 和内容层（EVIDENCE.md）。
- 【读】倒置时 World/Suite 把**窗口**整体转 180°（`MWTurn`，绕屏幕中心），并把内容层 Mango 自己带的半转抵消掉；它们只认自己写的 transform：窗口、根视图（最外层透传视图）、内容层的值只要被别人改成不认识的，就记 `CONFLICT`，停到下次注销；检查还要求窗口、根视图、内容层及其子视图的 `sublayerTransform` 恒等、根视图是满屏的。
- 【读】Mango 自己的位置/大小调节会把 transform 换成纯缩放，还改 anchorPoint/position/center（MangoPanda 里应用 `PillGlass.PosAdjust/PosX/PosY/PosScale` 的那个函数）。
- 【推】所以调节一动，World 看到自己负责的那几层被别人写了，就判冲突并撤下倒置，这就是「调大小或位置时倒置失效」。

本插件的做法：

```
屏幕上的位置 = 窗口（25/24 缩放；倒置时再转 180°） ∘ 本插件的调节（只在中间一层透传视图上） ∘ 系统原本的布局
```

- 只写**一个** transform：根视图（最外层透传视图）下面的那几个透传视图（预期是第二层）。窗口、根视图、内容层、容器，本插件一个都不碰，也不用 `sublayerTransform`，所以 World/Suite 的所有检查照样成立。
- 这个 transform 写在**窗口自己的坐标系**里。窗口转 180° 时，窗口自己的坐标系跟着转，所以窗口坐标 = 你看到的方向（只差一个统一缩放，25/24 会换算进去）。同一个 transform 在正着和倒置时都对，旋转只是叠在外面，调节里没有任何和朝向有关的计算。
- 这一点有主机上的 C 测试：`tests/island_test.c` 把窗口按「缩放 + 原点 + 可选半转」建模，随机生成两万组大小/位置/锚点，检查正着和倒置时你看到的位置都等于「以锚点缩放再平移」，并检查来回转动和调节时、回到默认值时都得到原样。
- 写入后还会立刻校验：节点上三个点经图层树换算到窗口坐标，必须落在算好的位置（误差 0.6pt 内）；不对就撤回并停止，日志里记 `VERIFY FAILED` 和实际数值。校验只用图层树，不读屏幕方向。
- 绝不抢：节点上只在是 identity 或者就是本插件上次写的值时才写；看到别人写的非 identity 值就让开（日志 `has a transform that is not ours`），别人改回 identity 又会重新应用。调节回到默认值时本插件什么都不拥有，系统原样。

**缩放中心（0.2.0 起和 Mango 一致）**：【读】Mango 把被调节视图的 anchorPoint 设成 (0.5, 42 / 视图高度)，即水平居中、视图顶端往下 42 点（视图自己的点）。本插件从被调节节点的顶端量起，同样往下 42 点、水平居中。被 Mango 调节的是不是这个满高的透传视图是【推】（依据是它拿 42 去除视图自己的高度）。0.1.0 用的 29.5（11pt 上边距加 37pt 药丸的一半）是按公开机型尺寸估的，已换掉。`AnchorY` 在 `settings.plist` 里能改，默认 42。

滑块范围（大小 0.60–1.50，左右/上下各 ±80 点）是本插件自己定的；Mango 设置页里滑块的范围没有读到【缺】。

【推】用的是第二层透传视图，窗口局部坐标等于视觉坐标，没有别人写这一层。**【缺】**这几条在真机上是什么样，第一次运行的日志会说（见下文）。

## 安装与使用

1. 装 deb，注销一次。
2. 设置 → 灵动岛 →「模式」选 Pro 或 Pro Max，点「应用模拟灵动岛」，确认，手机会立刻注销。
3. 要换分辨率：「预设」选一项，点「应用分辨率」，确认，同样会立刻注销。想回到默认就点「恢复默认分辨率」。
4. 让灵动岛出现（放一首歌，或开一个计时器），回设置 → 灵动岛 调「大小/左右/上下」。
5. 倒置时检查：把手机倒过来，灵动岛仍在屏幕视觉上方、方向对；调大小、调位置，倒置不应消失，岛要跟着你调的方向动。

要换样式（Pro ↔ Pro Max）：先「取消模拟」再「应用模拟灵动岛」，或者直接换了模式再点「应用」（已经是灵动岛的值时会按新样式改写）。

用本页的调节时，请把 Mango 自己的灵动岛位置、大小调节关掉（归零）。机型模拟、分辨率和 Mango 的「灵动岛模拟」是同一个办法，改的是同一批文件，只开一个。

## 出问题怎么退

- 设置里：「取消模拟」「恢复默认分辨率」「恢复默认大小和位置」。
- 设置页进不去：新建空文件 `/var/mobile/Library/Preferences/DynamicIsland.restore`（还原机型和画布并注销），或 `DynamicIsland.disabled`（只停掉大小/位置调节，不改机型和画布）。
- 全都不行：备份在 jbroot 下的 `/var/mobile/Library/Application Support/DynamicIsland/MobileGestalt.original.plist`。把它拷回 `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`，重启手机。画布：删掉 `/private/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist`（那个链接）和 `/var/tmp/com.apple.iokit.IOMobileGraphicsFamily.plist`，再注销或重启手机。如果那个位置上原来有过别的文件，备份在 `…/Application Support/DynamicIsland/IOMobileGraphicsFamily.foreign.plist`。

## 第一次上机时看什么

设置页里「导出诊断日志」。里面按这些行判断：

| 日志行 | 意思 |
|---|---|
| `INSTALLED 灵动岛 …` | 插件在 SpringBoard 里起来了，带系统版本、机型、**面板像素高 `nativeHeight`**（13 mini 预期 2340，见上）和系统此刻报告的屏幕 `live=宽x高`（没有画布时和面板一样；应用画布后看它变不变） |
| `CHAIN window …` | 灵动岛窗口的真实层级、frame、transform、窗口缩放单位 `unit`、窗口方向（`turnFixed`/`turnModel`）。**这是第一手证据**，和上面【推】不符就以它为准 |
| `NODE new …` | 找到被调节的那一层，类名和父类 |
| `APPLY node=… transform=…` | 写入并通过校验，附带写入时窗口是正着还是已转 |
| `VERIFY FAILED …` | 写进去的位置和算的不一样，已撤回；`want`/`got` 是三个探测点的期望和实测 |
| `has a transform that is not ours` | 那一层上有别人的 transform，已让开 |
| `ORIENTATION statusBar=… turnFixed=… turnModel=…` | 方向变化（`statusBar` 2 是倒置）和窗口转没转 |
| `STATE adjust=…` | 当前状态：`applied`/`default`/`off`/`no-window`/`verify-failed`/`conflict`… |
| `REQUEST apply …` / `REQUEST canvas-apply …` | 机型模拟、分辨率请求和结果（带 `mode=`、`preset=`） |
| `GUARD restore at launch targets=… -> done=…` | 崩溃保护触发，`targets` 1 是机型、2 是画布 |
| `RESTORE FILE -> model … \| canvas …` | 还原文件触发 |

最想确认的几件事：
1. 机型模拟后系统灵动岛是不是出现了；`nativeHeight` 是不是 2340。
2. 应用分辨率后屏幕是不是真的换了画布（黑屏/花屏要重新注销）；如果系统不认这两个键，画面不会变，日志也没有异常。
3. 正着调大小/位置，岛有没有按预期动，触摸（点、长按、上下滑）是否正常。
4. 倒置（`turnFixed=turned`）时调节，岛是否仍在正确的一侧、没有被撤下，调节方向是否是你看到的方向。
5. 倒置中途来回切换正着/倒置，调节值不丢、岛不错位。

## 没做的 / 已知限制

- 上面「灵动岛一栏里没有做的」那一整张表。没有常驻的空闲小药丸，液态玻璃也没有。
- 大小是整体缩放；大于 1 时展开态可能超出屏幕。
- 倒置本身（窗口转 180°、内容层抵消、点击兜底）仍由 World 或 Suite 负责，本插件不重复做；没有它们时倒置的岛不会被本插件转正。
- 只在 iOS 16 上生效，类名和层级是按 16.5 的日志写的；模拟在别的系统版本上没有验证（和 Mango 一样要求 16.1 及以上）。
- 状态栏、锁屏、主屏等别的界面在模拟和换画布之后的样子（机型值和画布会影响所有读它的地方）没有评估，和 Mango 的模拟是同一类风险。
- 本机没有 iOS SDK，Objective-C 部分只能靠 CI 编译；C 部分在主机上编译并跑过测试。

## 检查

- 主机上：`gcc -std=c11 -Wall -Wextra -Werror island/tests/island_test.c -lm && ./a.out`。覆盖：调节与半转的组合（正着/倒置一致）、回到默认值时无痕迹、窗口单位、所有权不抢、机型值备份/还原/拒绝规则、Mango 的 `isCurrentlyEnabled` 判定（按真实控制流跑出的组合表）、iOS 16.1 闸、10 个预设逐项、画布路径决策（建/换/留底/拒绝/放回）、画布下的面板尺寸、崩溃保护时序与按目标撤销。
- CI（`.github/workflows/island.yml`，和 World/相机的 `build.yml` 分开，互不影响）：同一个测试用 clang 再跑一遍，然后用 Theos 构建 deb，`tools/check_island_package.py` 检查包的结构，并确认动态库里真的有机型和画布两半的键与路径；失败时也会上传构建日志。构建通过不等于上机验证。

## 文件

| 文件 | 内容 |
|---|---|
| `IslandMath.h` | 调节的几何、所有权判定，纯 C |
| `IslandPolicy.h` | 机型值、备份、还原、iOS 16.1 闸、`isCurrentlyEnabled`、分辨率预设与画布路径决策、崩溃保护，纯 C |
| `Settings.h` | 设置、请求协议、路径（jbroot 与真实路径），SpringBoard 和设置页共用 |
| `Disguise.h/.m` | 读写 MobileGestalt 缓存、备份、还原、崩溃保护状态、注销 |
| `Canvas.h/.m` | 分辨率画布：写画布文件和链接、读回核对、留底与放回、撤销；记面板自己的尺寸 |
| `Tweak.m` | SpringBoard 里的插件：找层级、写调节、校验、响应请求、启动时的崩溃保护与还原文件、日志 |
| `prefs/` | 设置页（PreferenceLoader） |
| `tests/island_test.c` | 主机上的 C 测试 |
| `MANGO-SIMULATION.md` | Mango 灵动岛模拟各项功能的依据 |
