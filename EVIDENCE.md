# MangoUpsideDownWorld 0.3.0-alpha3：证据与边界

这是本次新实现，不是从关联对话中取回的既有 World 源码，也不是给 Fix alpha2 改名。

## 已证实的输入

- Mango 镜像 UUID：67C0D7C2-4487-3FD2-9535-067745AE4B8F。
- Mango 静态分析：DecoratedAppSceneView 的类方法 mango_currentInterfaceOrientation（原镜像 IMP 0x721d0）；本地通知 MangoInterfaceOrientationDidChange。仅读取方向，不更改 Mango 的方向报告。
- 真机日志：MangoUpsideDownProbe(3).log，SHA256 bdeca97908ca702dbfc3d4d6497f1890f91bab9998fec229186577eea07082d8。
- 日志 2441–2450 行的真实父链：Mango host → SAUIElementView → UIView → _SBSystemApertureContainerViewContentView → UIView → SBSystemApertureContainerView → 三层 SBFTouchPassThroughView → SBSystemApertureWindow。
- 内容层已带 180° transform；三层触摸穿透视图仍为 identity；窗口有 25/24 缩放。
- 最外层触摸穿透视图固定坐标大小约 375×811.80556，屏幕是 375×812。不能忽略窗口缩放或直接写死 812 点的父坐标。
- 用户纠正：只有通知视觉正常，触摸仍不正常，其他形态视觉和触摸也异常。因此不采用“展开已修复”的旧结论。

## alpha1 真机结果（用户报告，三份日志）

alpha1 已经把收起态的岛放到了倒置下的正确位置，这是 MangoUpsideDownWorld.log 里稳定出现的 `TRACK` / `WORLD orientation=2 … canceled=1` 所对应的效果。同时报告了三个缺陷：

1. 触控灵动岛期间岛内内容倒置，停止触控或触发一定动画后恢复。
2. 触控方向上下颠倒：手指下滑执行的是上滑。
3. 少数情况下岛仍出现在屏幕底部，复现路径是锁屏后在音乐播放状态点亮屏幕。

日志给出两条关键约束：

- 全程没有 `HIT fallback`。窗口原生 hitTest 一直返回非空且非窗口自身，命中位置的修正来自根视图整体旋转本身，窗口命中兜底在实机上是未触发的路径。方向颠倒不可能来自兜底逻辑。
- 全程没有 `CONFLICT`。每次 4 Hz 校正读到的内容层 transform 都等于 World 上次写入的值，说明 Mango 对内容层的每一次写入都经过 `setTransform:`，World 的 hook 全部可见。

## 0.2.0-alpha2 的改动（针对上面第 1 条）

alpha1 对内容层的抵消发生在原始 setter 之后：先还原成 Mango 的倒置值，调用原始实现，再由 `Reconcile` 写回正向值。Mango 是在动画块里写这个 transform 的（Probe 日志中内容层在动画期间出现纯缩放值），所以原始 setter 一执行，UIKit 就已按“当前显示的正向 → 倒置”建立了 CAAnimation。之后写入的模型值改不了这条动画的终点，presentation layer 整段动画都朝倒置插值，直到动画结束才被模型值拽回。这与“触控期间倒置、松手或动画结束后恢复”完全对应，包括恢复的时机。

alpha2 改为规范化传入值：在内容层的 `setTransform:` hook 里，先判定传入的基向量是否是干净的半周倒置，是则把符号取反后再交给原始实现，使 UIKit 建立的动画两端都是正向的。提交的模型值与 alpha1 由 `Reconcile` 写入的值相同，所有权记录也按 sweep 的方式写入，因此转回竖屏仍把 Mango 自己的值交还。过渡角度、已经正向的值、非有限值一律原样透传，`suspended` 或根视图未被翻转时不改写。

同时把 `ApplyWorld` 的每个静默 return 改为限频的 `SKIP reason=… mangoOrientation=…` 记录（同一原因 5 秒内不重复，成功后清空），用于把第 3 条从推测变成证据。这一项只增加日志，不改变任何几何行为。

抵消算子下沉为 `MWCancelTurn` 与 `MWInvertedBasis`，由 sweep 和 `setTransform:` 两条路径共用同一判定，CI 的 world_math_test 覆盖其保持缩放与位移、自逆、以及对已正向/镜像/过渡角度/退化/非有限输入的拒绝。

## 0.3.0-alpha3 真机结果（用户报告）与本版改动

0.2.0-alpha2 修好了触控期间的倒置闪动，但引入了新问题：以音乐播放为例，未展开状态下长按灵动岛的瞬间会闪现一次旋转动画（似乎每次激活——不论触控还是其它方式——只要岛出现就会闪一次），展开态关闭时也会闪现旋转动画，且这次是慢速的、从倒置转正向的旋转。

原因是 alpha2 的内容层 `setTransform:` hook 仍然调用了 `Begin(s)`。`Begin` 会在真正调用原始实现之前，先用 `performWithoutAnimation` 把内容层的 transform **同步写回** Mango 的上一次原始（倒置）值——这一步本身不产生动画，但它改变了模型层当时持有的值。紧接着 hook 调用原始实现，把我们替换的正向值交给它；如果这次调用处于 Mango 自己开的动画事务里（长按激活、关闭动画都是这种事务），Core Animation 会以调用瞬间的模型值作为该属性动画的起点——也就是刚被 `Begin` 写回的倒置值，终点是我们替换的正向值。于是 Core Animation 真的把"倒置→正向"这段翻转做成了一次可见动画，长按/关闭的动画时长越长，这个翻转就越慢越明显。

修法：内容层的 `setTransform:` hook 不再调用 `Begin`/`End`，不在真正调用之前做任何同步写回。直接判定传入值是否为干净的倒置基向量，是则把替换值交给原始实现，所有权记录按替换值直接写，不经过还原-重算这一圈。这样模型层在两次调用之间始终停留在"正向"这一侧，Core Animation 捕捉到的起点和终点都是正向值，不会经过符号翻转的那一刻。World 自身的写入（`SetOwned`/`RestoreOne`，运行在 `Busy=YES` 期间）原样放行，不受影响。定期扫描（`Reconcile`/`ApplyWorld`）仍然全程包在 `performWithoutAnimation` 里，从未是闪动的来源；问题只出在这一个 hook 里"先还原、再用动画事务写入"的间隙。

副作用：内容层的 `setTransform:` 不再在每一帧都触发一次同步的全量 `Reconcile`（之前 `End` 在 `Depth` 归零时会触发）。这个视图自身的规范化已经在 hook 内联完成，其它被追踪的 root 仍由 250ms 定时器和方向变化通知驱动，不依赖这次调用。

## 尚未处理

- 触控方向上下颠倒（第 2 条）。World 只旋转窗口内部的视图，窗口与屏幕坐标系本身没翻，手势位移若在窗口或屏幕空间计算，符号就与视图内部坐标相反。下一步待验的方向是把半周旋转上移到 `SBSystemApertureWindow.transform`（其 frame 为 {0,0,375,812}、center 恰为屏幕中心、现有 transform 为纯 25/24 缩放，符号取反即绕屏幕中心的精确半周）。若位移是在 UIScreen 固定坐标系或 HID 层计算，UIKit 层无法修正。本版未改动。
- 岛落到屏幕底部（第 3 条）。alpha2 只加了跳过原因日志，未改判定。需要真机复现后读 `SKIP` 行才能定性；另需确认异常时岛内文字对倒置视角是正还是倒，以区分是 Mango 的方向状态问题还是 World 的几何判定问题。

## 保留风险

1. 模型坐标数学验证不能证明 presentation layer 动画、手势捕获或自定义系统点击区域正确。规范化传入值只覆盖经过 `setTransform:` 的写入；直接写 CALayer 或用 CAAnimation 另行驱动的路径不在其内。
2. 未重写 safe area。内部布局仍由系统/Mango计算；展开间距和展开方向必须真机核验。
3. 未取得其他实时形态的完整日志；不承诺独立 fallback UIWindow、窗口外图层或独立浮层得到修正。
4. 直接 CALayer 写入冲突时不猜测新基线，停止该实例；需 respring 清理。父布局读取变换后的 frame 仍有反馈风险。
5. 同一系统 aperture 根里的其他元素也跟随倒置，这是整体方案的作用范围。只在已核对 UUID 和 iOS 16.5 下启用。
6. 没有倒置插件本身的二进制，不能确认其是否修改 compositor / HID 或仅修改 UIKit。本版没有 backboardd 注入。

测试覆盖：局部语法检查；1000 组仿射半周变换及逆变换；日志中的缩放/非对称中心案例；重复旋转抵消；抵消算子的缩放/位移保持与自逆；倒置基向量判定的接受与拒绝用例；非有限数值拒绝；CI 将检查真实 deb 的 arm64e、RootHide 链接、签名数据、SpringBoard 注入过滤及仅含两个 payload 文件。均不等同于真机验证。第 1 条的修复本身也未经真机验证。
