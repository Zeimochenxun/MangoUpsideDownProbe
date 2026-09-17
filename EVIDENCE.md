# MangoUpsideDownWorld 1.0.1：证据与边界

这是本次新实现，不是从关联对话中取回的既有 World 源码，也不是给 Fix alpha2 改名。

**关于 1.0.0 这次版本重排**：alpha14 之后曾经有 alpha15/15b/15c 三个版本（手动开关 `ManualOn`、全局 `UITouch` 定位 hook、音量键长按改造），目的是继续追灵动岛拖动方向问题；但那个手动开关本身在真机上一直点不动（`ARM READY` 有、`ARM TAP` 没有），问题定位到"触摸没到这个视图还是识别器没触发"这一步就没再继续。用户决定放下这条还没查完的线，把代码内容退回到 alpha14（`git checkout <alpha14 commit> -- .`，新提交，不是重写历史，alpha15 系列的三个提交完整保留在 git log 里），在这个更简单、已经稳定的基础上做两个跟灵动岛无关的新需求。版本号相应从 `0.X.0-alphaN` 换成独立的 `1.0.0` 起点，避免跟仓库历史上已经用过的 `alpha2` 混淆。悬浮球、长按一键复制、`SPLITPROBE`/`CONTENTDUMP` 等诊断工具全部原样保留——这次两个新功能的日志同样都经过 `Log()`，会自动进入长按复制的历史里，不需要额外接线。

**1.0.1 是 1.0.0 装机真机反馈后的一次修正**：方向锁定的目标从"倒置时强制转正"改成了"倒置时锁在倒置状态"；Face ID 锁屏诊断被证实此路不通（Face ID 本身在架构层面就不支持倒置，见下方对应小节），已从代码里移除，不再是"待完成"事项。

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

## 0.4.0-alpha4：把半周旋转从根视图移到窗口本身（触控方向上下颠倒）

之前三个版本都是让 `ApplyWorld` 旋转 root（`SBSystemApertureWindow` 的直接子 `SBFTouchPassThroughView`），窗口本身的 transform 从未被触碰。这对**位置**和**内容朝向**是够的——旋转 root 和旋转 window 对渲染结果的效果完全等价（对任意仿射函数 F 都有 `F(2a-b)=2F(a)-F(b)`，只要 pivot 用 `convertPoint:fromCoordinateSpace:` 换算到对应的父坐标系，两种做法对根视图在固定坐标系里的最终位置给出完全相同的结果，与 UIKit 如何用 center/bounds 定义 transform 的具体细节无关）——但对**手势方向**不够：root 和 content（root 内部，经过取消旋转后）相对固定坐标系是一致的（都被"转了半周"），而窗口本身从未被转，仍然与固定坐标系一致。凡是拿窗口局部坐标（或等价的，未经视图变换的原始/固定坐标）算手势位移的代码，读到的符号就与拿 content 局部坐标算的相反——这正好是"触发位置对,方向反"的成因：手指往下滑,在固定坐标系里 Y 是减小的（因为用户是倒着看屏幕),而 content 内部坐标系(已经整体转了半周)把这解读为"往下",和窗口/固定坐标系解读的"往上"正好反号。

只比较组合链的线性部分(旋转/缩放,与位移无关,因为手势的是位移量 `p2-p1`,常数项在减法里直接消掉)验证了这个符号分歧:现有做法下 window 的线性部分是正对角(未转),root 和 content 的线性部分是负对角(已转)——两者符号相反。改成转窗口后,三者的线性部分全部是负对角,一致。

本版把 `ApplyWorld` 里 `SetOwned` 的目标从 `root` 改成 `w`(窗口):增加一条对窗口自身基向量的"未被改动"前置检查(与原有的 root-basis 检查同构),pivot 直接用固定坐标系的屏幕中点(窗口没有 superview,它自己的 center/frame 已经是直接用固定坐标系表达的,不需要像 root 的 pivot 那样先经过 `convertPoint:fromCoordinateSpace:` 换算)。`RestoreWorld` 相应改为还原 `s.parent`(即窗口)而不是 root。内容层的取消旋转逻辑完全不变——它只看 content 自身相对固定坐标系的基向量,与外层转的是 root 还是 window 无关。`WorldHit`/`HookHit`/`HookInside` 也不需要改——它们用的是 UIKit 自己的 `convertPoint:`/`hitTest:`,自动适配变换实际所在的层级。

`WorldMath.h` 本身不需要新函数：`MWTurn` 已经是通用的，只是这次喂给它的是窗口的 transform/center，而不是 root 的。数学正确性用符号证明和线性部分的数值验证覆盖，没有新增 C 单测——现有的模糊测试已经覆盖了 `MWTurn` 的核心代数性质（对任意仿射输入的自逆性），这次改动没有引入新的数学原语，只是把已验证的函数用在了另一个视图上。

## 0.5.0-alpha5：真机报告"下滑仍执行上滑"，静态分析 mango.dylib 找候选 hook 点，加只读探测

用户在 0.4.0-alpha4 上真机复验：倒置下拖动灵动岛时手指轨迹是对的（长按后的展开动画跟手），但上下滑动仍被判反——手指下滑触发的是上滑该有的动作。同时观察到 Mango 自身的分屏等操作界面完全没有跟着倒置，用户据此提出：如果要从根本解决，只能让 Mango 整个操作界面的手势/朝向逻辑本身也跟着转，而不是只在 World 这一侧转坐标系。

这已经超出"读它公开暴露的方向状态、在 SpringBoard 侧做坐标系变换"的范围，用户明确要求评估反汇编 `Mango` 仓库（`https://github.com/Zeimochenxun/Mango/tree/main/mango`）里的编译产物。核查结果：

- 该目录只有 9 个文件，全部是 Mach-O 动态库（`.dylib`）和注入过滤配置（`.plist`），没有任何 `.m`/`.h`/`.swift`/Xcode 项目文件——不是可编辑的源码，是运行时载荷本身。`mango(1).dylib` 的 LC_UUID 为 `67c0d7c244873fd29535067745ae4b8f`，与 `Tweak.xm` 的 `VerifiedMango()` 校验的 UUID 完全一致，确认这正是 Tweak.xm 已经在运行时打交道的同一个二进制。
- 当前环境没有反汇编工具（IDA/Hopper/Ghidra），没有对编译后的机器码做逐条逻辑分析。做的是和 `Orientation()` 已经在做的同一类事——读取 Objective-C 方法名字符串。这些名字即使二进制被 strip 过仍必须原样保留在 `__TEXT,__objc_methname` 段里，否则 `objc_msgSend` 无法在运行时按名字分发消息；这是可以安全静态读取的元数据，不是被保护的实现细节。
- 在 `mango(1).dylib` 的 4168 个真实方法名（用 `^[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z0-9_]*)*:?$` 过滤掉属性类型编码噪音后）里，挑出的候选：
  - `pillSwipeDownAction` / `setPillSwipeDownAction:` / `pillSwipeUpAction` / `setPillSwipeUpAction:` / `dismissPill` / `dismissPillAnimated:`——名字直译就是"岛的上滑/下滑动作"，是本次症状最可能的落点：拖动跟手可能走的是一段连续读位置的代码（已被窗口转正的坐标系覆盖），而"这次算上滑还是下滑"可能是另一段只看一次性符号、不经过任何坐标转换的独立判断。
  - `mango_orientationDidChange:`——Mango 自己的方向变化回调，与已知的 `mango_currentInterfaceOrientation` 同源。
  - `mango_prepareTopDismissReverseGeometryForInteractiveMirror` 及一组 `_topDismissRevDx/Dy/ECx/ECy/EH/EW/LenSq/SCx/SCy/ScaleMin`——名字里直接带"Reverse"和"InteractiveMirror"，说明 Mango 内部已经有一套自己的"反向几何/镜像"机制用在某个从顶部关闭的手势上，具体用途和是否与倒置相关未知。

方法名只指出"去哪找"，不能证明"内部怎么算的"——这仍是基于命名的假设，不是确认的行为证据。本版新增 `ProbeMangoSelectors()`：运行时用 `objc_copyClassList`/`class_copyMethodList` 遍历所有已加载的类，找出真正**定义**（不是继承）上述候选方法的类，把类名和方法名记入日志。纯只读，不 hook、不改变任何行为，只是把"字符串猜测"变成"运行时坐标"，安装成功后调用一次。

## 0.6.0-alpha6：`PROBE` 真机结果——排除两条假线索，锁定 `MangoPillManager`，列全部方法

真机日志的 `PROBE` 行：

```
PROBE class=MangoPillManager sel=dismissPill
PROBE class=MangoPillManager sel=dismissPillAnimated:
PROBE class=MangoAppLibraryPickerView sel=mango_prepareTopDismissReverseGeometryForInteractiveMirror
PROBE class=DecoratedAppSceneView sel=mango_orientationDidChange:
```

`pillSwipeDownAction`/`pillSwipeUpAction` 及其 setter **零匹配**。结合之前扒出的完整字符串上下文（紧邻的是 `UIButton` 类型的 `_pillSwipeDownActionButton`、`UILabel` 类型的 `_pillDismissDelayLabel`、`UISlider` 类型的 `_pillDismissDelaySlider`），这几个名字现在看是 Mango **设置界面**里"选择下滑/上滑执行什么动作"的配置控件，不是运行时手势处理代码——设置页面的类要用户打开设置才会加载，装上就跑一次的探测自然找不到。这条线索排除。

`mango_prepareTopDismissReverseGeometryForInteractiveMirror` 挂在 `MangoAppLibraryPickerView` 上——这是"应用资源库选择器"，与灵动岛是完全不同的界面。之前把它当作"Mango 内部已有倒置相关机制"的证据是错的，这条也排除。

唯一落到实处的：**`MangoPillManager`** 确认已加载，定义了 `dismissPill`/`dismissPillAnimated:`，是灵动岛（pill）控制器类的强候选。但只探测了 8 个猜的名字，没有看这个类真正暴露了哪些方法。

本版新增 `ProbeMangoPillManager()`：直接用 `objc_getClass("MangoPillManager")` 取类，沿它自己的父类链（遇到 `NS`/`UI`/`OS_` 前缀的苹果框架类就停，避免把 `NSObject`/`UIResponder` 几千个无关方法也倒出来，最多走 8 层）用 `class_copyMethodList` 列出每一层**直接定义**的全部方法，记入日志。不再猜名字，直接看这个类真实暴露了什么。仍然纯只读，不 hook 任何东西。

## 0.7.0-alpha7：`MangoPillManager` 真机结果——不是手势代码，改成实时抓真正的调用方

真机日志给出了 `MangoPillManager` 的完整方法列表(17 个):

```
init / dealloc / .cxx_destruct
setupNotificationObservers
handleAppForegroundChange: / handleLockStateChange: / handleInterfaceOrientationChange:
showPillForBundleID:primaryText:secondaryText:(两个重载) / showFallbackPill:
dismissPill / dismissPillAnimated:
isPillVisible / activePillForBundleID: / removeActivePillForBundleID:
activePills / setActivePills:
```

没有任何 pan/swipe/touch/gesture 方法。`MangoPillManager` 是纯粹的内容生命周期协调器——靠监听通知(前后台切换、锁屏、方向变化)决定何时显示/收起什么内容，完全不碰手势识别器或触摸坐标。

这排除了 `MangoPillManager`,也意味着处理灵动岛拖动方向的代码大概率不在 Mango 自己的类里——很可能是苹果自己在 SpringBoard/UIKit 里的私有代码，World 一直是"绕着走"而不是"拥有"它。之前静态字符串扫描找到的 `handlePan:`/`panGestureRecognizer`/`translationInView:` 等名字，现在看更可能属于 Mango 里别的界面(设置面板、启动台)，与灵动岛拖动无关。

继续按名字猜类、列方法这条路已经把最有希望的候选都查完了，收益递减。本版改用运行时实时抓取:新增 `IsInsideTrackedRoot()`(检查一个视图是否是某个已跟踪 root 或其后代，通过 `Roots` 哈希表查找，不依赖任何名字或签名猜测)，以及对 `UIPanGestureRecognizer` 的公开、有文档的 UIKit API `translationInView:`/`velocityInView:` 的只读 hook:调用原始实现拿到真实返回值、原样返回(不改变任何行为)，只在这个手势的 `.view` 落在已跟踪的 root 子树内时才把调用方视图和返回值记入日志(限频，同一 0.05 秒内只记一次)。`Roots` 为空时(即世界未处于倒置激活状态)这段代码只做一次 count 检查就返回，和现有的逐帧几何 hook 是同一量级的开销。

已知的局限:如果真正起作用的识别器是一个重写了这两个方法的私有子类，hook 基类的实现就看不到那次调用——真机测试如果完全没有 `GESTURE` 行，说明的是这一点，不是"没有手势发生"。

## 0.8.0-alpha8：放弃"继续转几何"，改为在读数处翻转固定坐标系增量

alpha7 的 `GESTURE` 探测在用户提供的日志里**一行都没有出现**（日志结尾 `811289528` 距 alpha8 前的安装 `811289451` 有约 76 秒）。这可能是那段窗口内没有实际做倒置滑动测试，也可能是真正的识别器是重写了这两个方法的私有子类从而绕过了基类 hook；暂时无法区分。

但另一条推理已经足以否定前四版的整条思路：**一个视图的渲染矩阵与它的触摸坐标矩阵是同一个矩阵**（触摸走其逆）。所以任何 transform 都不可能只翻转画面、而不同等地翻转同一子树内任何代码读到的坐标。alpha1–3 转 root、alpha4 转窗口（窗口是 World 能触及的最顶层视图），两次真机复验方向都仍是反的——这就排除了"链条上还有某一层符号不一致"这整类解释，包括 alpha4 赖以成立的那一条。

剩下唯一自洽的解释是：做方向判断的那段代码**根本不在这棵子树里**，它读的是屏幕的 `fixedCoordinateSpace`，即物理屏幕位置。窗口的 transform 只是把窗口摆在那个空间**之内**，无法重新定义那个空间本身；于是这个读数者永远看到手指真实的物理位置，完全不受 World 的任何操作影响——而这正是 bug：World 把灵动岛从物理屏幕顶部搬到了物理底部，读数者却仍按它被编写时的布局来判断上/下。每一次滑动都会反，而且再怎么加转都会一直反。

这也同时解释了此前看起来自相矛盾的两个事实：**连续拖动跟手**（它持续重新读取位置、并经由已翻转的子树渲染，两半都在同一个被翻转的空间里因而相互抵消），而**离散的上/下判定不跟手**（它在固定坐标系里只取一次符号，从未经过那次翻转）。

所以本版不再动几何，而是在那个固定坐标系增量进入岛手势处理的唯一入口处做一次取反：hook 公开有文档的 UIKit API `UIPanGestureRecognizer` 的 `translationInView:`/`velocityInView:`，仅当该识别器自身的 `.view` 位于某个 World 正在翻转的 root 子树内时生效。新增 `InsideTurnedRoot()` 沿 superview 链（最多 64 层）找到第一个带 `MWWorldState` 的视图，并要求 `!s.suspended && s.outer.applied`——与 `OwnedContent` 判定内容变换所用的完全同一个条件，理由也相同：那次翻转正是使固定坐标系增量的视觉含义反过来的原因，因而也正是取反它成立的精确条件。已 SUSPEND/CONFLICT 的 root 被刻意排除（此时世界并未翻转，增量必须原样透传）。非有限值与非主线程同样原样透传，与本文件其他几何路径一致地 fail closed。

x 轴同样取反：半周旋转会同时反转两个轴，所以被翻转的岛上左/右和上/下一样是镜像的。只取反 y 会修好上报的症状、却把同一个 bug 的水平那一半留在原处，并且引入一个镜像（镜像不是旋转），几何上不自洽。

**置信度与如何被推翻**：上述推理是自洽的，但那个具体的读数者**尚未被观测到**。如果真正起作用的是重写了这两个方法的私有子类，或者读数者取的是 `UITouch` 原始位置而非 pan 识别器的增量，那么本版不会产生任何可观测的变化、方向依旧是反的——那个结果是有信息量的，不是回归，也正是此处保留 `GESTURE` 日志（现在记录 `raw=` 与 `turned=` 两个值）的原因。届时下一步应是记录该识别器的真实类名，而不是再猜一次。

## 0.9.0-alpha9：新增只读触摸/手势追踪工具，不是新的修复尝试

alpha8 的置信度说明留了一个未闭合的问题：`GESTURE` 探测在用户提供的日志里一行都没出现，无法区分"那段时间没测"还是"真正的识别器是重写了 `translationInView:`/`velocityInView:` 的私有子类从而绕过了 hook"。继续靠猜名字、列方法这条路（alpha5-6 已经走到收益递减）解决不了这个问题——需要的是在触摸真实发生的那一刻直接看运行时状态，而不是再猜一个类名去验证。

新增 `TraceTouches()`，由运行时开关 `TracePath`（同 `Disabled` 的建法，`Reconcile()` 里每 250ms 或方向变化通知时检查一次）控制，默认关闭：

- Hook 点是 `WindowClass`（`SBSystemApertureWindow`）的 `sendEvent:`——这是触摸事件到达这个窗口的最早一个可 hook 的公开入口，早于 `hitTest:withEvent:`/`pointInside:withEvent:`（这两个已经被 hook 用于命中兜底）。
- **严格只读，且顺序很关键**：hook 先调用原始 `sendEvent:`，再读取 `event.allTouches`。UIKit 是在原始实现内部完成命中测试并把结果写进 `UITouch.view` 的，如果反过来先读后调用，读到的会是还没被赋值的视图——这不是任意选择的写法，是保证读到的数据有效的必要顺序。不改变命中测试、分发顺序或任何返回值，与已有的几何修正逻辑完全独立、互不影响。
- 对每个触点记录：`phase`（`UITouch.phase`，公开属性）、该点在窗口坐标系和 `fixedCoordinateSpace`（物理屏幕坐标）下的位置、命中视图的真实类名，以及沿该视图 superview 链（上限 32 层，与文件里其它遍历同一量级的防御性上限）收集到的**全部**手势识别器——用 `UIView.gestureRecognizers` 这个公开属性读取，去重后逐个记录其真实运行时类名（`NSStringFromClass`，不是猜测）、`state`、`numberOfTouches`。
- 这解决的正是 alpha8 留下的问题：不管起作用的识别器有没有重写 `translationInView:`/`velocityInView:`，它只要挂在这条 superview 链上就会出现在 `recognizers` 列表里，类名是运行时读出来的事实，不是推理。
- 同时把这个类名也补进了已有的 `GESTURE api=... class=...` 行——`TurnDelta` 里原本已经拿到 `self`（触发调用的识别器实例），只是没有记录它的类；一行 `NSStringFromClass(self.class)` 就能看出是不是纯 `UIPanGestureRecognizer` 本身。
- 频率控制：与 `GESTURE` 同样用 0.05 秒节流（一次拖动每帧回调多次），且只在 `Tracing` 为真时才做任何工作——`Tracing` 是一次静态 BOOL 读取，关闭时这个 hook 的开销与调用原始实现之外几乎为零，不影响未开启诊断时的正常行为。
- 未新增任何几何原语或修正逻辑，`WorldMath.h`/`world_math_test.c` 不变；这里全部是运行时对象自省（`gestureRecognizers`、`state`、`numberOfTouches`、`phase`、`convertPoint:toCoordinateSpace:`），无法在脱离 UIKit 运行时的 C 单测里覆盖，与文件里其它同样依赖真实视图层级的诊断代码（`ProbeMangoSelectors`、`ProbeMangoPillManager`、`WorldHit`）用的是同一类验证方式：只能靠真机日志核验，不靠单测。

## 0.10.0-alpha10：把 alpha9 的记录同时喂给一个悬浮球，不改变记录内容本身

用户反馈拿日志文件太麻烦：Filza 在 `/var/mobile/Library/Preferences/` 新建文件失败（用复制已有文件再粘贴重命名绕过了这个问题，见安装环节的对话），事后再翻文件、通过 SSH 或 Filza 把内容发出来这一整条路径本身也是额外负担。本版不改变 alpha9 记录**什么**（`TOUCH`/`GESTURE` 行的字段不变），只改变记录之后**去哪**：同一条格式化字符串除了写入 `Log()`（文件不变），也传给新增的 `DebugRecord()`，直接显示在屏幕上。

- 新增一个独立的 `UIWindow`（子类 `MWDebugWindow`），窗口层级设到 `UIWindowLevelAlert+100000`，确保盖在系统其它界面之上。窗口本身铺满全屏，但重写了 `hitTest:withEvent:`：只有悬浮球和展开面板这两个真实子视图能接住触摸，其它区域命中到窗口自己时一律返回 `nil`，让触摸穿透到下面的正常界面——这和文件里 `SBFTouchPassThroughView` 这个类名本身要求的行为是同一件事，只是这次是我们自己新建的窗口需要自己满足这个要求。
- **这个窗口从未被 `Discover()` 登记进 `Roots`**，所以 `ApplyWorld`/`RestoreWorld`/`OwnedContent`/`InsideTurnedRoot` 都不会碰到它：它始终按正常方向渲染，拖动它自己的 `UIPanGestureRecognizer` 也不会被 `TurnDelta`取反（`InsideTurnedRoot` 沿 superview 链找的是带 `MWWorldState` 的 Root，这棵视图树里没有）。这是设计使然，不是需要验证的假设——诊断工具本身必须在被诊断的东西行为异常时仍然可用。
- 悬浮球可拖动（`UIPanGestureRecognizer`，纯本地状态更新，不涉及任何 World 几何）、点按展开/收起（`UITapGestureRecognizer`）。历史缓冲是一个上限 300 条的 `NSMutableArray`，超出后从最旧的开始丢弃；展开时把整个缓冲拼接显示在一个不可编辑的 `UITextView` 里，每次新记录自动滚动到底部。
- 面板本身设为 `selectable=NO`：长按面板会把当前 `.text`（也就是整份历史）一次性写入 `UIPasteboard.generalPasteboard`，比逐字选择再复制更直接。选择/放大镜交互和这个长按手势是同一类手势（都基于长按），两者同时挂在同一个 `UITextView` 上会相互抢夺识别，所以关掉了前者，只留复制这一个用途；`selectable=NO` 不影响滚动，滚动是 `UITextView` 继承自 `UIScrollView` 的独立手势。复制后面板背景闪一下白色再淡回原色，作为唯一的成功反馈（没有引入 toast/alert 这类更重的 UI）。
- 只在 `Tracing`（同 alpha9 的文件开关）为真时才创建/显示；关闭时隐藏但不销毁，历史和悬浮球位置保留，重新开启不会重置。创建本身是幂等的（`if(DebugWindow)return;`），从 `Reconcile()`（恒在主线程）里被调用，不会重复初始化。
- 与几何测试同理，这里全部是运行时 UIKit 对象操作（窗口层级、hitTest、手势、文本视图），不是新的坐标数学，`WorldMath.h`/`world_math_test.c` 不变，无法脱离设备真机验证。

## 0.11.0-alpha11：真机 TOUCH 日志给出真实类名，否定了 alpha8 赖以成立的前提

用户用 alpha10 的悬浮追踪工具在真机上做了多次点按/拖动，日志里的 `TOUCH` 行第一次给出了处理灵动岛触摸的真实类名：

```
TOUCH phase=Began window={164.8,65.0} fixed={203.3,744.3} view=_SAUIPortalView recognizers=SBSystemApertureLongPressGestureRecognizer(state=Began,touches=1),_UISystemGestureGateGestureRecognizer(state=Possible,touches=1),_UISystemGestureGateGestureRecognizer(state=Possible,touches=0)
```

两个新事实：

1. **`SBSystemApertureLongPressGestureRecognizer`**——命中视图父链上真实挂载的手势识别器之一，从类名判断极可能是 `UILongPressGestureRecognizer` 的私有子类，**不是** `UIPanGestureRecognizer` 的子类。Objective-C 是单继承，一个类不可能同时是这两者的子类；如果这个类名判断成立，它就根本不会响应 `translationInView:`/`velocityInView:`——这两个方法只在 `UIPanGestureRecognizer` 上有定义，不在 `UIGestureRecognizer` 基类上。
2. **`_SAUIPortalView`**——命中视图的真实类名，此前从未在任何日志或静态分析里出现过。`SA` 前缀与已知的 `SBSystemAperture*` 系列命名一致（`SBSystemApertureWindow`/`SBSystemApertureContainerView`），说明灵动岛的可视内容除了已知的 `_SBSystemApertureContainerViewContentView` 之外，触摸命中的还有这一层，此前完全未知。

**这两件事一起，直接否定了 alpha8 赖以成立的前提**：alpha8 的整套推理建立在"读数者是某个 `UIPanGestureRecognizer`（或其未覆写这两个方法的子类）"之上，据此把 hook 打在了 `UIPanGestureRecognizer` 类对象本身。如果真正处理拖动的识别器是 `SBSystemApertureLongPressGestureRecognizer`，它的方法解析完全在 `UILongPressGestureRecognizer → UIGestureRecognizer` 这条独立的继承链上，与 `UIPanGestureRecognizer` 的类对象和方法表毫无关联（Objective-C 的方法调度按接收者自身的类走各自的继承链，两条链之间不存在任何交叉）——`InsideTurnedRoot`/`TurnDelta` 挂的 hook 在这条路径上不可能被调用一次。这也是本次日志里**完全没有出现 `GESTURE` 行**的直接解释：不是没有做拖动测试，是这两个 hook 打在了错的类上，从一开始就不可能被触发。同时这也让 alpha7 那次"一行都没记到"的空探测第一次有了确定的解释，而不再是"没测到"和"被私有子类绕过"两种可能之间悬而未决——现在可以确定是后者，而且知道了具体是哪个类。

**alpha8 的修复本身不必回退**：`TurnDelta` 的取反逻辑只在 `InsideTurnedRoot(view)` 为真时生效，而这个判定走的是 `view.superview` 链找 `MWWorldState`，与被 hook 的是哪个手势类无关——但既然这条 hook 路径本身从未被调用，它在实际拖动时从未执行取反，"是否触发过取反"和"手指方向是否已经修好"这两件事目前完全没有被这份日志验证过，仍然是悬案。

本版新增两类只读探测，做法沿用本文件一直坚持的方法论（先看真实运行时状态，再决定往哪一步走，不猜测行为语义）：

- `LogOwnMethods()`：对 `SBSystemApertureLongPressGestureRecognizer` 和 `_SAUIPortalView` 各做一次方法列表转储，用法与 alpha6 对 `MangoPillManager` 的 `ProbeMangoPillManager()`（该函数本身在 alpha7 被移除，但方法沿用）完全一致：沿类自身的 superclass 链，遇到 `NS`/`UI`/`OS_` 前缀的苹果框架类就停（最多 8 层），只列每一层**直接定义**（`class_copyMethodList`，不含继承）的方法名，装上后各跑一次，不区分是否开启 `Tracing`。
- `LogLongPressProbe()` + 对 `SBSystemApertureLongPressGestureRecognizer` 的 `locationInView:`/`locationOfTouch:inView:` 的只读 hook：这两个方法定义在 `UIGestureRecognizer` 基类上，任何子类（不论是 pan 还是 long press）都响应，不像 `translationInView:` 那样专属于某一个具体子类——如果这个类的方向判断代码是靠反复调用这两个方法读位置、自己在内部做差分，这里就会看到调用；如果完全看不到，说明它走的是别的路径（大概率是重写了 `touchesBegan:`/`touchesMoved:` 之类的私有实现，直接用原始 `UITouch` 坐标）。用 `MSHookMessageEx` 直接把 hook 挂在这个具体的类对象上——即使这两个方法的真实实现是继承自 `UIGestureRecognizer` 从未被这个子类覆写，`MSHookMessageEx` 也只影响这一个类，不会波及其他任何调用同名继承方法的类；这正是本文件里 `INSTALL_HOOKS` 宏一直在用的同一个技术（`layoutSubviews`/`setFrame:`/`setBounds:`/`setCenter:`/`setTransform:` 在 `PassClass`/`ContentClass`/`WindowClass` 上大多也是继承自 `UIView` 而非自己覆写的）。调用原始实现、原样返回，不改变任何行为，只记录：`LPROBE api=... point={x,y} state=...`。
- 两者都是新增的诊断能力，不修改 `WorldMath.h`/`world_math_test.c`，也不修改任何几何/手势修正逻辑本身——`TurnDelta`/`ApplyWorld`/`ContentHookTransform` 未变。

**下一步该看什么**：真机装上本版后重新做一次拖动测试，重点看两类新日志：`CLASSDUMP` 会给出这两个类真正暴露的方法名（如果其中有类似 `_updateWithTranslation`/`handleDrag` 之类看起来像方向判断入口的名字，就是下一个该 hook 的候选）；`LPROBE` 有没有出现决定了"这个类到底怎么读位置"——有的话说明确实经过 `locationInView:`/`locationOfTouch:inView:`，可以在这个入口上重复 alpha8 的取反逻辑；完全没有则说明要换成 hook 这个类自己的私有方法（`CLASSDUMP` 列出的名字就是候选来源），而不是任何 `UIGestureRecognizer` 公开 API。

## 0.12.0-alpha12：让悬浮面板真正拿到"全部"日志，不只是几类显式接了的行

用户反馈：本想只靠"长按悬浮面板"这一步就把所有诊断信息发出来，不用再碰 Filza/SSH。但 alpha10-11 里悬浮面板只是被动接收——`DebugRecord()` 只在 `LogGestureFix`/`LogGestureSkip`/`TraceTouches`/`LogLongPressProbe` 这四个具体调用点被显式调用，`Log()` 本身不知道悬浮面板的存在。这意味着 `CLASSDUMP`（alpha11 这次最需要看的那两行）、`TRACK`、`WORLD`、`SKIP`、`CONFLICT`、`HIT fallback` 等其它所有日志类型都只写进了文件，长按面板拿到的是不完整的子集——且这个子集会随着以后新增日志类型继续悄悄漏掉新的种类，因为"要不要接入面板"变成了每个调用点各自决定的事。

修法是把 `DebugRecord(s)` 的调用从这四个具体函数里移进 `Log()` 自身：`Log()` 是本文件目前 25+ 处日志调用**唯一**的出口（每一行不管来自哪个函数，最终都调用 `Log(NSString *s)`），在这一个点上镜像进悬浮面板的历史，就让"文件日志"和"悬浮面板"在结构上永远保持一致——不是靠记住给每个新日志点都加一遍 `DebugRecord`，而是这件事根本不需要再做。原来四个调用点各自的 `Log(s);DebugRecord(s);` 简化回单独的 `Log(s)`，避免重复记录同一行两次。

`Log()`（第 51 行）的定义在文件里出现得早于 `DebugRecord()`（约第 588 行）和 `DebugSetVisible()`（约第 574 行）的定义，所以在文件顶部（`StateKey` 之后）为这两个函数各加了一条前向声明——这与 `DebugSetVisible` 本身在 alpha10 就已经需要的前向声明是同一个原因、同一种写法。

**新发现的线程安全缺口**：`DebugRecord()` 会直接写 `UILabel.text`/`UITextView.text`，这两个都是 UIKit 对象，只能在主线程访问。alpha11 引入的 `LogLongPressProbe()`（喂 `LPROBE` 行）是当时**唯一**一个在调用 `DebugRecord` 之前没有先检查 `[NSThread isMainThread]` 的路径——`LogGestureFix`/`LogGestureSkip` 的调用方 `TurnDelta` 已经检查过，`TraceTouches` 只在 UIKit 主线程分发事件时被调用。既然现在 `Log()` 本身无条件触达悬浮面板，这个缺口本身变得更容易踩到（虽然它在 alpha11 就已经存在，不是这次改动引入的），顺手在 `LogLongPressProbe` 里补了同样的主线程检查。文件里其它所有 `Log()` 调用点都已经确认位于某个更外层的主线程检查之后（`Reconcile()`/`Begin()`/`WorldHit()`/`ContentHookTransform()`/`Install()` 各自的入口检查），不需要重复加。

不影响任何几何或手势判定逻辑——`WorldMath.h`、`ApplyWorld`、`ContentHookTransform`、`TurnDelta` 均未改动，这一版纯粹是诊断链路本身的完整性修复。

## 0.13.0-alpha13：让悬浮追踪窗和其它插件也跟着倒置转，而不是只诊断灵动岛

用户要求：灵动岛之外，"任何插件"（包括 Mango 的分屏、以及本工程自己的日志悬浮窗）目前都不会跟着屏幕倒置转，这次要一起解决。前置研究澄清了两件容易混的事：

1. 用户已确认设备上本来就装着"另一个真正的倒置插件"（`README.md` 里"保留 Mango 和原来的倒置插件"这句话说的就是它），也就是让 `Orientation()` 报告 `PortraitUpsideDown` 的那个真正方向切换,本身已经存在、World 从未负责实现它。研究了开源的 `34306/upsidedowned` 和它的源头 `khanhduytran0/TrollPad`（两者代码都读过，全文搜了 `Aperture`/`SAUI`/`portal`/`dynamic` 均为零匹配），确认它们采用的手法——`SBTraitsSceneParticipantDelegate._isAllowedToHavePortraitUpsideDown`/`_orientationMode`、`SpringBoard.homeScreenRotationStyle`、`SBApplication.isMedusaCapable`、`supportedInterfaceOrientations` 加 mask——只解决"允许声明这个方向"，从未涉及 System Aperture 这一整个私有子系统。这与 alpha11 的结论一致：灵动岛的触控问题出在一个读物理固定坐标、根本不查方向状态的私有类，换哪种方式触发倒置都不会碰到它。因此这次改动**不**移植这套 idiom 伪装逻辑——本仓库的目标一直是让 Mango/其它插件跟 World 已经存在的倒置状态保持一致，不是重新实现倒置本身。
2. "插件不跟着转"分成两类，处理方式完全不同：
   - **本工程自己写的悬浮窗**（`MWDebugWindow`）：是纯粹的 `UIWindow`，不涉及任何私有手势类，之前 alpha10 特意让它"从不被 World 登记为 Root"以保证诊断本身不受几何修正干扰——但这也是它至今不跟着转的唯一原因，纯属这次之前没接。UIKit 对普通 `UIWindow` 的 `transform` 本身就会让其下所有公开手势识别器的 `translationInView:`/`locationInView:`/hit-testing 自动按转后的方向解读,不需要任何 alpha8 那种针对 fixed-space 读数的额外修正。新增 `DebugSetTurned(BOOL)`,在 `Reconcile()` 每次 tick 都根据当前 `active`（`Enabled&&Orientation()==PortraitUpsideDown`,与 World 判断是否要转灵动岛用的同一条件）设置或清除 `DebugWindow.transform` 为绕中心的 180°旋转，与面板可见性（`DebugSetVisible`,只在 `Tracing` 时才创建/显示）完全独立，即使不开 trace 也持续保持同步,不必等到面板被点开。
   - **其它插件（Mango 分屏等）**：真实的类名和实现方式未知，本文件此前唯一验证过的私有手势类是灵动岛自己的 `SBSystemApertureLongPressGestureRecognizer`,直接猜一个类名去 hook 分屏正是 alpha1-8 在灵动岛上吃过的亏。所以这次新增的是和 alpha11 `CLASSDUMP` 同一思路的**只读探测**,不是修复：`ProbeOtherWindows()`（只在 `Tracing` 时跑,与 `TraceTouches` 同一个开关,不需要额外文件）遍历主屏幕上除 `SBSystemApertureWindow`/自家悬浮窗外的每个窗口,用现有的 `MWInvertedBasis` 判据（灵动岛内容层倒置识别用的同一个函数）逐层检查其视图树里是否有任何视图相对 `fixedCoordinateSpace` 呈现"已经是倒置基向量"的样子。若找到,记一条 `SPLITPROBE window=<类名> inverted=<命中视图类名列表>`,每个窗口类名只记一次防止刷屏。这只回答"分屏用的是哪个窗口/哪些视图看起来已经倒了",不代表这些视图的触控也一定对——灵动岛的教训就是内容朝向对、触控仍可能反,下一步要看真机 `SPLITPROBE` 结果再决定分屏具体怎么跟进,不能跳过这一步直接照搬灵动岛的 hook 集合。

两处改动都不影响现有的灵动岛几何/手势逻辑（`ApplyWorld`/`ContentHookTransform`/`TurnDelta`/`WorldMath.h` 均未改）,悬浮窗的转正只影响它自己的 `UIWindow.transform`,探测只读、不写任何视图。

## 0.13.0-alpha13 真机结果，与 0.14.0-alpha14 的修法

用户开 trace 后做了一次长按/拖动测试，并打开了 Mango 分屏、进行了 Mango 相关操作。日志给出两组独立的新事实：

**灵动岛拖动方向——`CLASSDUMP`/`LPROBE` 的组合结果**：`SBSystemApertureLongPressGestureRecognizer` 自身只定义了一个方法——`touchesMoved:withEvent:`；`_SAUIPortalView` 定义的全是渲染配置相关方法（`setSourceView:`/`portalLayer`/`_configurePortalViewIfNeeded` 等），没有任何手势代码，排除。同一份日志里有约 10 次 `TOUCH phase=Moved`，但 `LPROBE`（`locationInView:`/`locationOfTouch:inView:`，`UIGestureRecognizer` 基类都有的公开取位置方法）总共只触发 4 次，且几乎全部落在 `Began`/`Cancelled` 状态切换的瞬间，持续拖动过程中（`Changed`）整场只出现 1 次。如果方向判断真的靠这两个方法算，应该随每次 `Moved` 持续密集触发；实际几乎不触发，说明这个类拿手指位置大概率没有走 `UIGestureRecognizer` 自己的这两个方法，而是在它重写的 `touchesMoved:withEvent:` 里直接读传入的 `UITouch` 对象自己的 `-locationInView:`/`-previousLocationInView:`（**注意**：`UITouch` 也有一个同名方法 `locationInView:`，跟 `UIGestureRecognizer` 的是两个完全不同类上的同名方法——这次 `InstallLongPressProbe()` 用 `MSHookMessageEx` 精确 hook 的是后者，根本碰不到 `UITouch` 自己那个）。这是具体、可验证的下一步方向，但本版没有据此新增或修改任何 hook：下一步如果要继续追，更安全的做法是直接给 `touchesMoved:withEvent:` 本身加 hook（范围完全锁定这一个类），而不是 hook 全系统都在用的 `UITouch`。

**`SPLITPROBE` 的假阴性——问题在探测范围，不在判据**：这次日志里 `SPLITPROBE` 命中了 `SBCoverSheetWindow`/`SBControlCenterWindow`/`UITextEffectsWindow`/`SBHomeScreenWindow`/`SBFloatingDockWindow`/`SBWindow`/`SBMainSwitcherWindow`/`SBBannerWindow`——基本是 SpringBoard 自己界面的全部（主屏、控制中心、锁屏、悬浮 Dock、多任务切换、通知横幅、键盘），证实了 alpha13 分析里提到的"另一个真正的倒置插件"确实在系统层面对这些窗口做了真正的整体旋转。但**没有任何一行提到 Mango 或分屏**，即使用户这次确认已经打开分屏并做过操作。

原因是 alpha13 的 `ProbeOtherWindows()` 显式跳过了任何 `isKindOfClass:WindowClass`（即 `SBSystemApertureWindow`，灵动岛自己的窗口）的窗口，理由是"里面的内容已经被这个文件其它逻辑处理过了"。但 `EVIDENCE.md` 第 10 行记录的父视图链——`Mango host → SAUIElementView → UIView → _SBSystemApertureContainerViewContentView → UIView → SBSystemApertureContainerView → 三层 SBFTouchPassThroughView → SBSystemApertureWindow`——和 alpha11 `TOUCH` 追踪都指向同一件事：真正被触摸命中的 `_SAUIPortalView`，是跟已知内容层（`_SBSystemApertureContainerViewContentView`）平级的另一个视图，不在它的子树里。alpha13 把整个灵动岛窗口都跳过，连这个视图也一起漏掉了——不是判据错，是范围错。

alpha14 的修法分两处，而不是简单地"不再跳过这个窗口"：

1. `ProbeInverted`/`ProbeOtherWindows` 现在会扫描所有窗口，灵动岛窗口也包含在内；但改为专门排除 `ContentClass` 这一个类本身（命中判定和递归都在这里停），而不是排除整个窗口。原因：`ApplyWorld`/`ContentHookTransform` 已经主动纠正过这个内容视图自己的朝向，纠正后它和它所有子视图，在固定坐标系里理应呈现"倒置基向量"——这是已经修好、生效中的状态，不是新发现。如果继续往它内部递归做这个判定，会把内容层内部本来就该倒置、早就在 `WORLD`/`TRACK` 里报过的图标、文字视图全部当成"新发现"报出来，是纯噪音，还会把真正的新信息埋起来。去重键也从"只按窗口类名"改成"窗口类名+这次找到的完整视图列表"，因为分屏打开关闭这类内容变化，不应该被"这个窗口类名之前报过一次"挡住不再记录。
2. 新增 `ProbeContentStructure()`，专门补上"不进内容层子树"留下的空白——它不问朝向对不对（那边的答案已知且没有信息量），只是把内容层内部**真实存在**的全部视图类名去重列出来，记一条 `CONTENTDUMP classes=...`，跟 alpha11 对手势类做 `CLASSDUMP` 是同一个思路，只是这次照的是视图树而不是方法列表。按去重后的完整类名集合去重记录，集合变了（比如分屏往里面加了新视图）会重新记一次，不会被更早、更短的一次记录挡住。

两个改动都只读，不修改任何几何/手势逻辑（`ApplyWorld`/`ContentHookTransform`/`TurnDelta`/`WorldMath.h` 均未改）。下一步：真机重新开 trace、再打开一次分屏，看 `SPLITPROBE` 里灵动岛窗口这次是否报出除已知三层 `SBFTouchPassThroughView`/`SBSystemApertureContainerView` 之外的新类名，以及 `CONTENTDUMP` 里是否出现一个明显不属于 `SAUIElementView`/通用 `UIView` 这类已知外壳的、看起来像分屏专用的类名。

## 1.0.0：方向锁定修复 + Face ID 锁屏诊断

用户提出两个跟灵动岛无关的新需求：(1) 倒置状态下开屏 Face ID 界面仍保持正向，每次都要把手机转回去才能看；(2) 倒置状态下点方向锁定，应该强制翻回正向而不是锁定在倒置状态。按用户自己定的方法论——先查有没有真实可用的信息，查不到才加只读探测——分别处理：

**方向锁定：查到真实依据，直接尝试修复**

`SBOrientationLockManager` 是从 iOS 7 就存在的私有 SpringBoard 单例（多个年代的运行时头文件存档都有记录）。为了不重蹈灵动岛前 8 版"猜类名直接下手"的覆辙，先找了一个真实存在、目前仍在维护的公开插件 [AVLock](https://github.com/gilshahar7/AVLock)（给系统自带视频播放器加方向锁定按钮），它的 `Tweak.xm` 里白纸黑字用的是：

```objc
[[%c(SBOrientationLockManager) sharedInstance] isUserLocked]
[[%c(SBOrientationLockManager) sharedInstance] lock]
[[%c(SBOrientationLockManager) sharedInstance] unlock]
```

另外从一份 2016 年（iOS 9.3）的运行时头文件存档里还能看到一个带参数版本 `-lock:(long long)arg1`，以及若干只读方法（`effectiveLockedOrientation`/`userLockOrientation`/`isEffectivelyLocked`）——这条是更早的历史证据，没有被 AVLock 这类现役插件直接验证过，所以代码里这两个方法都要先过一遍这个文件已有的 `Signature()` 检查，验证不通过就什么都不装，跟这个文件对待其它私有方法的一贯做法一致。

同时确认了网上最常被提到的强制转屏手法——`[UIDevice setValue:forKey:@"orientation"]`——**在 iOS 16 上已经被苹果官方明确废掉**（苹果论坛版主原话："这个技巧不应该被使用……现在已经被修复，不再有任何效果"），所以这次完全没有用这个思路。

修法（1.0.0 初版）：新增 `InstallOrientationLockFix()`，hook `SBOrientationLockManager` 的无参数 `-lock`（Control Center 那个开关本身没有方向参数可传，大概率调的就是这个）。每次调用时读 `Orientation()`（这个文件已有的、读取 Mango 当前方向报告的函数）：倒置状态下不调用原始无参数实现，改为直接调用原始的带参数实现 `-lock:`，传入 `UIInterfaceOrientationPortrait`，把锁定目标本身纠正成正向；其它情况原样调用原始实现。

同时对带参数的 `-lock:` 单独挂了一个**只读观察 hook**，只记日志（`ORIENTATIONLOCK explicit-lock target=... currentOrientation=...`）、永远原样放行——用来收集真实数据：万一 Control Center 的开关实际调用的不是无参数版本，或者还有别的调用方（比如相机的方向锁定），这条日志能看出来。这个观察 hook 在 1.0.1 里原样保留，没有改动。

**这次改动的性质需要单独说清楚**：`SBOrientationLockManager` 是**这个文件历史上第一个不属于 Mango、而是整台手机共用的系统级单例**——之前所有 hook（`PassClass`/`ContentClass`/`WindowClass`/`SBSystemApertureLongPressGestureRecognizer` 等）都严格限定在已用真机日志验证过、只服务于 Mango 灵动岛自己的私有类上，出错的影响面天生被限定在灵动岛身上；这次挂的方法是 Control Center 开关、相机方向锁定等任何东西调用 `-lock` 都会经过的同一个对象。缓解手段是行为上的、不是结构上的：只有真的检测到"当前是倒置状态"这一个条件成立时才会真的改变行为，其它时候是原样透传——但风险的**类别**本身（系统级单例 vs. Mango 专属类）跟之前任何一次 hook 都不一样，这一点已经在实现前明确告知用户，由用户自己判断可以接受。这条结论在 1.0.1 依然成立，1.0.1 只改了检测到倒置后具体锁定到哪个方向，风险类别本身没变。

**Face ID 锁屏：没查到确切类名，加了只读探测——后续证实这条路线走不通，1.0.1 已移除**

两轮搜索都没找到锁屏 Face ID 提示界面对应的确切私有类名，所以最初不猜测下手，只加了诊断（`ProbeLockScreenViews()`，复用 `Tracing` 开关，扫描类名带 `CoverSheet`/`DashBoard` 的窗口，记录内部真实视图类名为 `LOCKPROBE` 日志）。真机测试拿到了完整的 `SBCoverSheetWindow` 视图树，逐个核对后没有任何类名带 "Biometric"/"FaceID"/"Auth"/"Nudge" 字样，`DashBoard` 前缀全程零命中。

用户随后指出一个更根本的问题：**iPhone 的 Face ID 摄像头本身是不是在识别倒置这件事上有硬性限制，不只是界面朝向问题**。查证结果确认了这一点：苹果官方支持文档明确写着 Face ID 在 iPhone 上只支持竖屏（早期机型）或竖屏+横屏（iPhone 13 及以后、iOS 16 及以后），从未提到支持倒置；iPad 则支持任意方向——这是平台级别的既有差异，不是这次装了什么补丁才出现的限制。更关键的是，真正的人脸/深度数据匹配发生在 **Secure Enclave**（跟主处理器物理隔离的独立安全协处理器）内部，SpringBoard 进程里的任何代码（包括这份文件能做的一切）从架构上就看不到、碰不到这个匹配过程。用户随后真机在倒置状态下实测面容解锁，确认识别失败，与这条限制的预期完全吻合。

结论：就算继续追下去、真的找到锁屏提示界面的类名并且改成正向显示，这也只能是纯视觉上的美化，无法让"倒置状态下解锁成功"这件事真的发生——这不是本文件的 hook 能力范围内能解决的问题，继续投入时间找类名不会带来任何实际效果。1.0.1 移除了 `ProbeLockScreenViews()` 及其调用点，跟 alpha7 发现 `MangoPillManager` 跟灵动岛手势无关后移除 `ProbeMangoPillManager()` 是同一个判断标准：一旦确认某条诊断的目标已经不可能达成，就不再留着占地方。

## 1.0.1：方向锁定的目标反过来——锁在倒置，而不是强制转正

用户装机测试 1.0.0 后反馈了两件事，共同促成了这次反转：

1. **横屏测试的结果不能说明倒置那边的行为对不对**：用户在**不支持横屏的主页面**上测试方向锁定，同样观察到"强制转正"。但主屏幕本身在这个项目的范围内根本不支持横屏（没有类似 `homeScreenRotationStyle` 这类允许主屏转横屏的 hook），所以横屏时点锁定，`-lock` 找不到一个"横屏"这个合法目标可以用，只能退回正向——这跟"锁定本来就会强制转正"是完全不同的两件事：一个是"目标选项根本不存在，只能落回默认"，另一个才是这次真正要处理的、倒置这个**已经是合法方向**（靠这台设备上另一个独立的倒置插件）时会发生什么。这条测试结果不能用来反推倒置状态下不装这次的 hook 会发生什么。
2. **真正的需求被重新表述了一遍**：最初的措辞是"倒置时锁定应该强制翻回正向"，但重新对齐后，用户明确的意图其实是相反的——World 这整个项目存在的目的就是让手机倒过来也能舒服使用，方向锁定这个功能在其它任何一个方向上的作用都是"保持我现在看到的方向，不要再自动转走"，所以倒置时它理应也是同一个作用：**锁定在倒置状态**，而不是把界面强行拉回正向、违背用户此刻正在倒置查看的意图。

修法：`HookLockNoArg` 检测到 `Orientation()==UIInterfaceOrientationPortraitUpsideDown` 时，调用 `OrigLockWithArg` 传入的目标从 `UIInterfaceOrientationPortrait` 改为 `UIInterfaceOrientationPortraitUpsideDown`——只改了这一个常量，其它逻辑（`Signature()` 校验、`OrientationLockFixOK` 兜底、对带参数版本的只读观察 hook）原样不变。对应日志字符串同步改为 `ORIENTATIONLOCK forced-to-upsidedown`。

## 尚未处理

- 岛落到屏幕底部。alpha2 加了跳过原因日志，未改判定。需要真机复现后读 `SKIP` 行才能定性；另需确认异常时岛内文字对倒置视角是正还是倒，以区分是 Mango 的方向状态问题还是 World 的几何判定问题。
- 灵动岛拖动方向问题本身停在 alpha14 已有的结论上（`LPROBE` 几乎不触发，怀疑走的是 `UITouch` 自己的 `locationInView:`/`previousLocationInView:`）——alpha15 系列曾经尝试推进这一点，但因为手动开关本身的真机 bug 没查完就被搁置，这次的 1.0.0/1.0.1 没有继续这条线，也没有回退掉 alpha15 的诊断结论，只是暂不基于那份代码继续。
- **Face ID 跟随倒置——已确认放弃，不是"尚未处理"**：真正的限制在 Face ID 认证流程本身（Secure Enclave 边界 + iPhone 平台从未支持倒置识别），不是这份文件能触及的范围，本节列出仅为存档，不再等待后续动作。
- 1.0.1 的方向锁定修复（锁在倒置状态）尚未真机验证：需要确认 `ORIENTATIONLOCK forced-to-upsidedown` 是否出现、锁定后界面是否真的保持倒置不被自动转走、Control Center 开关本身的视觉状态是否和实际锁定状态一致。

## 保留风险

1. 模型坐标数学验证不能证明 presentation layer 动画、手势捕获或自定义系统点击区域正确。规范化传入值只覆盖经过 `setTransform:` 的写入；直接写 CALayer 或用 CAAnimation 另行驱动的路径不在其内。
2. 未重写 safe area。内部布局仍由系统/Mango计算；展开间距和展开方向必须真机核验。
3. 未取得其他实时形态的完整日志；不承诺独立 fallback UIWindow、窗口外图层或独立浮层得到修正。
4. 直接 CALayer 写入冲突时不猜测新基线，停止该实例；需 respring 清理。父布局读取变换后的 frame 仍有反馈风险。
5. 同一系统 aperture 根里的其他元素也跟随倒置，这是整体方案的作用范围。只在已核对 UUID 和 iOS 16.5 下启用。
6. 没有倒置插件本身的二进制，不能确认其是否修改 compositor / HID 或仅修改 UIKit。本版没有 backboardd 注入。

测试覆盖：局部语法检查；1000 组仿射半周变换及逆变换；日志中的缩放/非对称中心案例；重复旋转抵消；抵消算子的缩放/位移保持与自逆；倒置基向量判定的接受与拒绝用例；非有限数值拒绝；CI 将检查真实 deb 的 arm64e、RootHide 链接、签名数据、SpringBoard 注入过滤及仅含两个 payload 文件。均不等同于真机验证。第 1 条的修复本身也未经真机验证。

---

# MangoUpsideDownCamera 1.0.0：证据与边界

**从这里开始，以下内容描述的是一个完全独立的第二个插件包**，不是上面 `MangoUpsideDownWorld` 的一部分——不同 dylib、不同 `control`、不同注入配置、不同开关文件，唯一的共同点是同一个 git 仓库、同一份对话历史。之所以拆成两个包而不是加进现有文件，见下面第一条。

## 需求与范围判断

用户提出的需求是：手机倒置时，**任意 App**（不只是系统自带相机）调用摄像头的界面都应该跟着转成倒置显示，不是只有灵动岛和 SpringBoard 自己的界面。

这跟 `MangoUpsideDownWorld` 已经做的所有事情有两处本质区别，都是先查证过再动手：

1. **注入范围**：`MangoUpsideDownWorld.plist` 用 `Filter.Bundles` 精确指定了唯一一个进程（`com.apple.springboard`）。SpringBoard 对别的 App 界面怎么显示完全没有话事权，"任意 App"这个范围要求代码真的跑在**每一个 App 自己的进程里**。查证了 MobileSubstrate 的 filter 机制：`Filter` 字典里除了常见的 `Bundles`（按 bundle ID 精确匹配）、`Executables`（按可执行文件名匹配），还有一个 `Classes` 键（数组），语义是"这个进程里如果加载了这个 Objective-C 类就注入"——这正是"任意 UIKit App，但不包括没有界面的系统后台服务"这个需求的现成机制，不需要完全不写 filter（那样会连 `launchd`、`backboardd` 这类系统进程都注入进去，风险高得多）。`MangoUpsideDownCamera.plist` 用的就是 `Filter.Classes=[UIApplication]`。
2. **判断依据**：`MangoUpsideDownWorld` 的 `Orientation()` 读的是 Mango 自己注入到 SpringBoard 里的一个类方法——这个类方法**只存在于 SpringBoard 进程里**，在任何其它 App 的进程里读它都是 `nil`。新插件改用 `UIDevice.currentDevice.orientation`——这是 UIKit 自己基于加速度计得出的物理姿态，每个进程里都一样、都是真实数据，跟 Mango、跟 SpringBoard 那边任何状态都没有关系。

**机制上的真实边界**：一个界面允不允许转到倒置方向，是通过 `-[UIViewController supportedInterfaceOrientations]` 这个方法逐个界面自己声明的。苹果自己的文档写着 iPhone 上不重写这个方法时的默认值就是"除了倒置都支持"——也就是说几乎所有 App 默认就是被排除在倒置之外的，要转就得自己在这个方法里加上倒置这个选项。而这个方法苹果自己的指导是"完全替换，不需要调用 `super`"——查证确认了这一点，意味着**只 hook `UIViewController` 这个基类自己的默认实现，对任何自己重写过这个方法的界面类完全无效**，因为那些类的实现根本不会走到基类的这份代码。这是结构性的限制：没有一个单一的 hook 点能透明地拦到"每个 App 自己写的每一种重写"，唯一能拦到某个重写的办法就是直接 hook 那个具体类自己实现的这个方法——但"任意 App"这个范围下，事先不可能知道所有 App 各自用了哪些类。

用户在了解这个限制后，明确选择了**先只做基类 hook 这一步，装机验证系统相机 App 是否已经足够，再决定要不要往风险更大的方向升级**（"全量覆盖"方案需要在每个进程启动时扫描整个 Objective-C 运行时、找出所有自己重写过这个方法的类逐个单独挂 hook，覆盖面更大但改动的类更多、风险面也更大——这次没有做，留作后续步骤）。

## 安全边界设计

- **独立打包**：新建 `camera/` 子目录，独立的 `Tweak.xm`/`control`/`MangoUpsideDownCamera.plist`/`Makefile`，不共享 `MangoUpsideDownWorld` 的任何代码（两个包各自编译、各自注入，即使其中一个的运行时逻辑写错，也不会拖累另一个）。CI (`.github/workflows/build.yml`) 复用同一次 Theos/SDK 安装，新增独立的 `make -C camera package` 构建步骤和独立的产物上传。
- **不进 SpringBoard**：`Install()` 显式排除 `com.apple.springboard` 这个 bundle ID——那边的倒置处理完全是 `MangoUpsideDownWorld` 的地盘，两份互不知情的代码同时改同一个进程的方向逻辑，正是这个项目自己的 `Conflicts:` 字段一直在防的那类冲突，只是这次防的对象换成了自己的另一个包。
- **构造函数阶段的时机问题（已修正）**：最初设计里想在 `Install()` 里顺带检查 `UIApplication.sharedApplication` 非空来确认"这是个真的 App 进程"，但 dylib 的 `__attribute__((constructor))` 是在 `dyld` 加载完所有依赖库、但在这个进程自己的 `main()`/`UIApplicationMain()` 跑之前执行的——那个时间点上，`UIApplication` 这个类肯定已经被 `dyld` 映射进内存了（`objc_getClass` 能查到），但**还没有任何 App 实例被创建**，`sharedApplication` 一定是 `nil`。如果真按最初的想法写，这个检查会在每一个正常 App 进程里都判定失败，导致 hook 永远装不上。改成只检查类是否存在（`objc_getClass("UIApplication")!=NULL`），这个检查在 dylib 刚加载的那一刻就已经真实有效，不依赖任何后续的运行时状态。
- **生成方向通知需要延迟到主线程 run loop**：`[UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications]` 依赖主 run loop 才能真正开始收到硬件方向更新，构造函数执行的那一刻 run loop 还没转起来，所以这一步单独 `dispatch_async` 到主队列延后执行；而给 `UIViewController` 打补丁本身只是改一个类的方法指针，不需要 run loop，所以这部分仍然在构造函数里同步完成，让 hook 尽可能早生效。
- **失败即透明放行**：跟 `MangoUpsideDownWorld` 的 `Signature()` 同一套做法（各自独立实现，不共享代码，但逻辑一致）——真机上如果 `supportedInterfaceOrientations` 的方法签名跟预期不符，直接不装任何 hook，行为跟没装这个插件完全一样；每次调用都会先拿到真实的原始返回值，只有确认当前物理姿态是倒置时才往上"加"一个倒置支持位，不是凭空捏造一个新的返回值——一个 App 自己已有的限制（比如"只支持竖屏，不支持横屏"）不受影响。
- **开关文件是实时检查，不是只在启动时查一次**：`MangoUpsideDownWorld` 有一个 250ms 的定时器持续检查自己的开关文件，即使不重启 SpringBoard，改动也能很快生效；这个新插件没有类似的常驻定时器（每个 App 进程只在真的被系统问到方向时才会跑到这段代码），所以特意把开关文件的检查放进了 hook 本身、每次调用都查一次，而不是只在 `Install()` 里查一次——否则关闭这个插件会要求先手动杀掉、重新打开每一个已经在跑的 App 才能确认生效，作为一个"紧急恢复手段"这个可靠性是不够的。

## 尚未处理（这个新包自己的，跟上面 `MangoUpsideDownWorld` 的清单分开记）

- 系统自带相机 App 在这次的基类 hook 下到底跟不跟转，尚未真机验证——README 已经把这一步列为装机后第一个要测的项目。如果不跟转，说明相机 App 自己重写了这个方法，需要真机确认后再决定是否升级到扫描整个运行时逐个 hook 的方案。
- 覆盖面广度（除了系统相机，还有多少第三方 App 会跟着转）尚未真机验证。
- 即使界面被允许转到倒置，实际拍摄/录制画面本身的方向是否正确，这次的改动管不到——取决于每个 App 自己怎么读设备姿态来设置拍摄方向，本身处理好四方向的 App 大概率自动跟着对，写死拍摄方向的 App 不会变。
- 首次被要求以倒置方向渲染的界面是否会出现视觉错位/图层错乱，这属于"从未被这样测试过的界面第一次被要求这样显示"固有的风险，任何做法都无法完全消除，只能真机逐一确认。
