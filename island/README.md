# 灵动岛 0.1.0（实验，未上机）

让带刘海的 iPhone（目标是 iPhone 13 mini，iOS 16.5，Dopamine RootHide，arm64e）用上系统自己的灵动岛，并且能调灵动岛的大小和位置；调节写在不会碰倒置的那一层，倒置时不会失效。

标记沿用之前的约定：**【读】** 在日志或二进制里看到过，**【推】** 由读到的东西推出来，**【缺】** 还没在真机上见过。这个版本的所有运行效果都是【缺】，下面写的是设计依据和上机时怎么看结果。

## 它做两件事

### 1. 机型伪装（Disguise.m）

SpringBoard 靠 MobileGestalt 里的 `ArtworkDeviceSubType` 判断要不要建灵动岛。改成 2556（14 Pro）或 2796（14 Pro Max），注销后系统自己的灵动岛就出现了。

- 【读】Mango Beta9 和 Beta12 的做法一样：改 `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist` 里 `CacheExtra["oPeik/9e8lQWMszEjbPzng"]`，读时用 `NSPropertyListMutableContainers`，写回 XML（format 100），原子替换，不 chmod，再调 `[FBSystemService exitAndRelaunch:YES]`。这是在 SpringBoard 里做的，本包也在 SpringBoard 里做：设置页只发请求（`request.plist` + Darwin 通知），SpringBoard 执行并回写 `result.plist`。
- 【推】机型值就是屏幕原生像素高：375×812pt 的机子（X/XS/11 Pro/12 mini/13 mini）是 2436，14 Pro 是 2556，14 Pro Max 是 2796。Mango 关闭伪装时“按 nativeBounds 推算原值”也是这条规则。
- 比 Mango 多出来的（都是为了能退回去）：
  - 第一次伪装前把整个缓存文件和原机型值备份到 `…/Application Support/DynamicIsland/`（`MobileGestalt.original.plist`、`original.plist`）。如果当前值已经是 2556/2796（比如之前用 Mango 改过），不会把它当成“原值”备份，还原时按屏幕推算（13 mini 是 2436）。
  - 设置页有“还原机型”。
  - 【崩溃保护】伪装后 SpringBoard 第一次重启就在 15 秒内死掉，下一次启动时插件会先把机型值写回去；活过 60 秒就解除保护。
  - 【还原文件】在 `/var/mobile/Library/Preferences/` 新建一个空文件 `DynamicIsland.restore`（Filza 或 ssh），插件下次启动或 5 秒内就还原并注销。
- 本机自带灵动岛（原生像素高 2556/2796）时直接拒绝，什么都不改。

### 2. 大小和位置（Tweak.m）

设置页里的“大小”“左右”“上下”。方向按你看到的算：向右、向下为正，正着拿、倒置时都一样，**倒置时不需要另外设置**。

## 为什么调节不会再让倒置失效

之前的故障，从仓库里的代码和证据能读出来：

- 【读】灵动岛窗口 `SBSystemApertureWindow` 本身带 25/24 的缩放；里面是三层 `SBFTouchPassThroughView`（identity），再往里是 `SBSystemApertureContainerView` 和内容层（EVIDENCE.md）。
- 【读】倒置时 World/Suite 把**窗口**整体转 180°（`MWTurn`，绕屏幕中心），并把内容层 Mango 自己带的半转抵消掉；它们只认自己写的 transform：窗口、根视图（最外层透传视图）、内容层的值只要被别人改成不认识的，就记 `CONFLICT`，停到下次注销；检查还要求窗口、根视图、内容层及其子视图的 `sublayerTransform` 恒等、根视图是满屏的。
- 【读】Mango 自己的位置/大小调节会把 transform 换成纯缩放，还改 anchorPoint/position/center（MangoPanda 里读偏好 `PillGlass.PosAdjust/PosX/PosY/PosScale` 的那个函数）。
- 【推】所以调节一动，World 看到自己负责的那几层被别人写了，就判冲突并撤下倒置，这就是“调大小或位置时倒置失效”。

本包的做法：

```
屏幕上的位置 = 窗口（25/24 缩放；倒置时再转 180°） ∘ 本包的调节（只在中间一层透传视图上） ∘ 系统原本的布局
```

- 只写**一个** transform：根视图（最外层透传视图）下面的那几个透传视图（预期是第二层）。窗口、根视图、内容层、容器，本包一个都不碰，也不用 `sublayerTransform`，所以 World/Suite 的所有检查照样成立。
- 这个 transform 写在**窗口自己的坐标系**里。窗口转 180° 时，窗口自己的坐标系跟着转，所以窗口坐标 = 你看到的方向（只差一个统一缩放，25/24 会换算进去）。同一个 transform 在正着和倒置时都对，旋转只是叠在外面，调节里没有任何和朝向有关的计算。
- 这一点有主机上的 C 测试：`island/tests/island_test.c` 把窗口按“缩放 + 原点 + 可选半转”建模，随机生成两万组大小/位置/锚点，检查正着和倒置时你看到的位置都等于“以锚点缩放再平移”，并检查来回转动和调节时、回到默认值时都得到原样（见下文“检查”）。
- 写入后还会立刻校验：节点上三个点经图层树换算到窗口坐标，必须落在算好的位置（误差 0.6pt 内）；不对就撤回并停止，日志里记 `VERIFY FAILED` 和实际数值。校验只用图层树，不读屏幕方向。
- 绝不抢：节点上只在是 identity 或者就是本包上次写的值时才写；看到别人写的非 identity 值就让开（日志 `has a transform that is not ours`），别人改回 identity 又会重新应用。调节回到默认值时本包什么都不拥有，系统原样。

【推】用的是第二层透传视图，窗口局部坐标等于视觉坐标，没有别人写这一层。**【缺】**这几条在真机上是什么样，第一次运行的日志会说（见下文）。

## 安装与使用

1. 装 deb，注销一次。
2. 设置 → 灵动岛 → 点“伪装为 iPhone 14 Pro 的灵动岛”（或 Pro Max），确认，手机会立刻注销。
3. 让灵动岛出现（放一首歌，或开一个计时器），回设置 → 灵动岛 调“大小/左右/上下”。
4. 倒置时检查：把手机倒过来，灵动岛仍在屏幕视觉上方、方向对；调大小、调位置，倒置不应消失，岛要跟着你调的方向动。

用本页的调节时，请把 Mango 自己的灵动岛位置、大小调节关掉（归零）。机型伪装和 Mango 的“灵动岛模拟”是同一个办法，两个只开一个。

## 出问题怎么退

- 设置里：“还原机型”“恢复默认大小和位置”。
- 设置页进不去：新建空文件 `/var/mobile/Library/Preferences/DynamicIsland.restore`（还原机型并注销），或 `DynamicIsland.disabled`（只停掉大小/位置调节，不改机型）。
- 全都不行：备份在 jbroot 下的 `/var/mobile/Library/Application Support/DynamicIsland/MobileGestalt.original.plist`。把它拷回 `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`，重启手机。

## 第一次上机时看什么

设置页里“导出诊断日志”。里面按这些行判断：

| 日志行 | 意思 |
|---|---|
| `INSTALLED 灵动岛 …` | 插件在 SpringBoard 里起来了，带系统版本、机型、原生像素高 |
| `CHAIN window …` | 灵动岛窗口的真实层级、frame、transform、窗口缩放单位 `unit`、窗口方向（`turnFixed`/`turnModel`）。**这是第一手证据**，和上面【推】不符就以它为准 |
| `NODE new …` | 找到被调节的那一层，类名和父类 |
| `APPLY node=… transform=…` | 写入并通过校验，附带写入时窗口是正着还是已转 |
| `VERIFY FAILED …` | 写进去的位置和算的不一样，已撤回；`want`/`got` 是三个探测点的期望和实测 |
| `has a transform that is not ours` | 那一层上有别人的 transform，已让开 |
| `ORIENTATION statusBar=… turnFixed=… turnModel=…` | 方向变化（`statusBar` 2 是倒置）和窗口转没转 |
| `STATE adjust=…` | 当前状态：`applied`/`default`/`off`/`no-window`/`verify-failed`/`conflict`… |
| `REQUEST apply …` | 机型伪装请求和结果 |

最想确认的三件事：
1. 正着调大小/位置，岛有没有按预期动，触摸（点、长按、上下滑）是否正常。
2. 倒置（`turnFixed=turned`）时调节，岛是否仍在正确的一侧、没有被撤下，调节方向是否是你看到的方向。
3. 倒置中途来回切换正着/倒置，调节值不丢、岛不错位。

## 没做的 / 已知限制

- 没有常驻的“空闲小药丸”（Suite 里的 MangoIdleIsland 是 Mango 的玻璃实现）；液态玻璃也没有。
- 大小是整体缩放；大于 1 时展开态可能超出屏幕。缩放中心是静止小岛的中心，【推】取 14 Pro 的 11pt 上边距加 37pt 高的一半 = 29.5pt（`AnchorY`，settings.plist 里能改）。
- 倒置本身（窗口转 180°、内容层抵消、点击兜底）仍由 World 或 Suite 负责，本包不重复做；没有它们时倒置的岛不会被本包转正。
- 只在 iOS 16 上生效，类名和层级是按 16.5 的日志写的；机型伪装在别的系统版本上没有验证。
- 状态栏、锁屏、主屏等别的界面在伪装后的样子（改机型值会影响所有读它的地方）没有评估，和 Mango 的模拟是同一类风险。

## 检查

- 主机上：`gcc -std=c11 -Wall -Wextra -Werror island/tests/island_test.c -lm && ./a.out`。覆盖：调节与半转的组合（正着/倒置一致）、回到默认值时无痕迹、窗口单位、所有权不抢、机型值备份/还原/拒绝规则、崩溃保护时序。
- CI（`.github/workflows/build.yml`）：同一个测试用 clang 再跑一遍，然后用 Theos 构建 deb，`tools/check_island_package.py` 检查包的结构。构建通过不等于上机验证。

## 文件

| 文件 | 内容 |
|---|---|
| `IslandMath.h` | 调节的几何、所有权判定，纯 C |
| `IslandPolicy.h` | 机型值、备份、还原、崩溃保护的决策，纯 C |
| `Settings.h` | 设置、请求协议、路径（jbroot），SpringBoard 和设置页共用 |
| `Disguise.h/.m` | 读写 MobileGestalt 缓存、备份、还原、崩溃保护状态、注销 |
| `Tweak.m` | SpringBoard 里的插件：找层级、写调节、校验、响应请求、日志 |
| `prefs/` | 设置页（PreferenceLoader） |
| `tests/island_test.c` | 主机上的 C 测试 |
