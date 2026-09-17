# MangoUpsideDownWorld 0.11.0-alpha11

新编写的实验兼容补丁。目标：iPhone 13 mini / iOS 16.5 / Dopamine RootHide / 已核对的 Mango 版本。尚未真机验证，不宣称全场景已修复。

采用完整灵动岛根视图倒置、内部重复旋转抵消及窗口触摸命中补偿。正常竖屏和横屏不施加倒置。仅注入 SpringBoard；不修改 Mango 原版，不涉及授权或付费逻辑。

## 本版相对之前版本的变化

alpha1 真机结果：收起态的岛已经能在倒置下显示在正确位置，但触控期间岛内内容会倒置、松手或动画结束后恢复；触控方向上下颠倒；少数情况下岛仍落在屏幕底部。

- alpha2 修了触控期间内容倒置：alpha1 在原始 setter 之后才把内容层改回正向，而 Mango 是在动画块里写这个 transform 的，UIKit 已按“正向 → 倒置”建好动画，后写的模型值改不了动画终点，于是整段动画都朝倒置插值。alpha2 改为在 `setTransform:` 里先把传入值规范化再交给原始实现。
- alpha2 引入了新问题：长按激活、展开态关闭时会闪现一次旋转动画（关闭时是慢速的倒置转正向）。原因是 alpha2 的 hook 仍调用了 `Begin`，会在真正调用之前同步把内容层写回 Mango 的原始倒置值，这个写回本身不产生动画，但会成为紧接着那次动画调用的起点，于是 Core Animation 把“倒置→正向”做成了一次可见动画。
- alpha3 修了这个问题：内容层的 `setTransform:` hook 不再调用 `Begin`/`End`，不在替换之前做任何同步写回，模型层在两次调用之间始终停留在正向一侧。
- alpha4 修了触控方向上下颠倒的**一部分**：之前三个版本都是转 root（灵动岛内部的一个视图），窗口本身从未被转，导致拿窗口/固定坐标算手势方向的代码和拿 content 内部坐标算的方向正好相反。alpha4 改成转窗口本身，位置和内容朝向的效果不变，但窗口现在也和 root/content 一致地转了半周。
- 真机复验发现：拖动跟手了，但上下滑动判断依旧反。这说明问题不完全在坐标系——很可能是 Mango 自己内部有一段判断"这是上滑还是下滑"的代码，不经过任何坐标转换，只看一次性符号。alpha5 加了一段只读探测：通过读取 `mango.dylib` 自身的方法名字符串（同一批二进制，UUID 已核对），找出几个名字上最可能相关的候选方法（`pillSwipeDownAction`/`pillSwipeUpAction`/`dismissPill` 等），运行时找出真正实现它们的类并记入日志。
- alpha5 的真机结果：`pillSwipeDownAction`/`pillSwipeUpAction` 零匹配，现在判断这两个其实是 Mango 设置界面里的配置控件，不是手势代码，这条线索排除；`mango_prepareTopDismissReverseGeometryForInteractiveMirror` 挂在应用资源库选择器上，跟灵动岛无关，也排除。唯一坐实的是 **`MangoPillManager`**（定义了 `dismissPill`/`dismissPillAnimated:`），是岛控制器类的强候选。alpha6 把探测从"猜名字"改成直接列出 `MangoPillManager` 自身及其父类链定义的全部方法。
- alpha6 的真机结果：`MangoPillManager` 全部 17 个方法都是内容生命周期/通知处理，没有任何 pan/touch/gesture 方法——排除了 Mango 自己的代码。alpha7 改成运行时实时抓，对上述两个公开方法只记日志、不改行为。
- alpha7 的真机结果：滑动期间**一行 `GESTURE` 都没记到**，无法区分是没测到还是被私有子类绕过。但另一条推理已足以否定前四版的整条思路：视图的渲染矩阵和触摸坐标矩阵是同一个，所以转任何一层都不可能只翻画面而不同等翻转同子树内读到的坐标——而转 root（alpha1–3）和转窗口（alpha4，窗口已是 World 能触及的最顶层）方向都仍是反的。唯一自洽的解释是：判断方向的代码读的是屏幕**固定坐标系**（物理位置），窗口的 transform 只把窗口摆在那个空间之内、无法重定义它，所以它永远看到手指的真实物理位置，而 World 把岛从物理顶部搬到了物理底部——它仍按"岛在顶部"判断，于是必然一直反。这也解释了"拖动跟手、但上下判定不跟手"：前者持续读位置并经翻转子树渲染、两半相互抵消，后者在固定坐标系里只取一次符号、从不经过那次翻转。
- 所以 alpha8 **第一次真正尝试修复方向**，且不再动几何：在那个固定坐标系增量进入岛手势处理的唯一入口处取反——仅当 `UIPanGestureRecognizer` 自身的 `.view` 位于某个正在翻转的 root 子树内时，对 `translationInView:`/`velocityInView:` 的返回值取反（x/y 都取，因为半周旋转同时反转两轴）。世界未翻转、已 SUSPEND、非主线程或非有限值一律原样透传。**这个修复基于推理而非观测**：如果真正的读数者是重写了这两个方法的私有子类、或读的是 `UITouch` 原始位置，alpha8 不会有任何可观测变化、方向依旧反——那是有信息量的结果而不是回归。
- alpha9 是纯诊断工具，不改变任何已有行为、不是新的修复尝试：新增运行时开关 `MangoUpsideDownWorld.trace`（建法同 `.disabled`），开启后在灵动岛所在窗口的 `sendEvent:` **之后**（不影响命中测试和分发本身）记录每次触摸的阶段、window/fixed 两种坐标、命中视图类名，以及该视图沿父链收集到的全部手势识别器——每个都带真实运行时类名、state、numberOfTouches。已有的 `GESTURE` 行也补上了识别器的真实类名。这样不必再靠推理：即使真正处理拖动的是重写了 `translationInView:`/`velocityInView:` 的私有子类，也能直接从 `TOUCH` 行的 `recognizers` 列表里看到那个类名。
- alpha10 同样是纯诊断工具：把 alpha9 这些记录同时喂给一个新增的屏幕悬浮球，不用再靠 Filza/SSH 事后去翻日志文件。悬浮球可拖动、显示已捕获行数，点一下展开成一块可滚动的面板，直接在屏幕上看完整历史；再点一下收起；长按面板一次性复制全部历史到剪切板。这个悬浮窗是完全独立的 `UIWindow`，World 从不把它当作 Root 登记，因此本文件里所有几何/手势 hook 都不会作用到它自己身上。
- **alpha11 的关键突破**：真机 `TOUCH` 追踪日志第一次给出了处理灵动岛拖动的真实类名——`SBSystemApertureLongPressGestureRecognizer`，不是任何 `UIPanGestureRecognizer` 子类。这一件事本身就解释了 alpha7 那次"一行 GESTURE 都没记到"的空探测：不是没测到，是 hook 打错了类——`translationInView:`/`velocityInView:` 是 `UIPanGestureRecognizer` 专有的方法，这个真正干活的类根本不响应它们。也意味着 alpha8 那次取反修复，即使真机上"看起来"方向对了，理论上也不可能是那次取反本身在起作用（它 hook 的方法在这条路径上从未被调用）。本版新增对新发现的两个类（`SBSystemApertureLongPressGestureRecognizer`、日志里同时出现的 `_SAUIPortalView`）做一次性方法列表探测（做法同 alpha5/6 对 `MangoPillManager` 那次），以及对这个手势类的 `locationInView:`/`locationOfTouch:inView:`（`UIGestureRecognizer` 基类都有的公开方法，不像 `translationInView:` 那样专属于 pan）加了只读探测 hook——纯读、不改行为，看它是否真的走这两个方法读位置。详见 EVIDENCE.md。

## 先准备恢复途径，再安装

1. 在手机仍正常时，确认电脑能通过 SSH 登录该手机，并保持终端连接；同时确认能从 Dopamine 关闭 tweak 注入后重新越狱。没有可用的恢复途径时先不要装。
2. 若安装后屏幕仍响应，但位置/触摸异常：用 Filza 在 `/var/mobile/Library/Preferences/` 新建空文件 `MangoUpsideDownWorld.disabled`。这个检查只看文件是否存在，不看内容——如果 Filza 的"新建文件"选项不可用或失败，复制该目录下任意一个已有文件、粘贴、再重命名为这个文件名同样有效。主线程正常时约 0.25 秒检测到，恢复可确认属于本补丁的变换；删除标记并 respring 才重新启用。
3. SSH 可用时，先在 RootHide 的越狱终端环境中运行 `command -v dpkg` 确认包管理命令存在，再用 root 执行 `dpkg -r com.chenxun.mangoupsidedownworld`，随后用已安装的越狱工具 respring。不要在 Windows PowerShell 本地执行 dpkg。
4. 若卡住/循环重启且 SSH 不可用：按音量加、音量减，然后持续按侧键至 Apple 标志强制重启；在未启用 tweak 注入的越狱状态下移除 World。关闭注入的具体控件以设备上的 Dopamine 界面为准。
5. Filza 手动恢复时，在 RootHide 当前真实 `.jbroot-…` 下找到 `Library/MobileSubstrate/DynamicLibraries/`，将 **MangoUpsideDownWorld.plist** 改为 `.plist.disabled` 后重新启动 SpringBoard；如实际包使用另一注入目录，以 `dpkg -L com.chenxun.mangoupsidedownworld` 清单为准。不要猜随机 jbroot 路径，不要删除 mango.dylib / MangoOSRendering.dylib。

## 安装与验收

- 先卸载 MangoUpsideDownFix 并 respring；建议停用旧 Probe 以减少高频日志。保留 Mango 和原来的倒置插件。World 包声明与 Fix 冲突，运行时也拒绝同时加载 Fix。
- 安装本包的 `iphoneos-arm64e.deb`，这是原生 RootHide 包，不要再次进行 rootless→RootHide 转换。
- 安装后 respring。先测普通竖屏和横屏，确认行为与安装前一致，再进入倒置。
- 本版**第一次改触控行为**，重点复验这一条：在倒置下手指在灵动岛上下滑动，触发的动作是否与手指方向一致。**顺带务必测一次左右方向**（本版同时取反了 x 轴）：左右滑动、以及展开态的左右排列和左右向操作是否仍然正常——如果左右反倒被弄反了，请立刻说，这条要单独退掉。
- 同时确认前几版已修好的没有回归：长按激活、展开、关闭全程岛内文字图标保持正向、没有旋转闪动；收起态位置正确；拖动跟手。
- 取日志找 `GESTURE` 行：本版记的是 `GESTURE api=... raw={x,y} turned={x,y}`，`raw` 是系统原值、`turned` 是取反后交给 Mango 的值。这些行只在倒置下滑动时才出现。**如果方向修好了，把有 `GESTURE` 行的日志发回来**；**如果方向依旧是反的，请特别说明日志里有没有 `GESTURE` 行**——没有的话说明我们 hook 的方法根本没被调用，那条推理就被推翻了，下一步要换方向查（见 EVIDENCE.md 的置信度说明）。
- 再分别验证：收起岛、通知、音乐/计时器、展开、收起；检查文字图标、左右排列、展开方向、点击、长按、拖动和岛外穿透；最后转回竖屏。
- 若要复现岛落到底部：锁屏后在音乐播放状态点亮屏幕，随后取日志查 `SKIP` 行。同时请记录异常时岛内文字对倒置视角是正还是倒 —— 这一条用于区分是 Mango 的方向状态问题还是 World 的几何判定问题。
- 日志位于 `/var/mobile/Library/Logs/MangoUpsideDownWorld.log`。`WORLD` 仅证明变换已应用；`SKIP` 说明该轮未施加修正及原因；`HIT fallback` 仅证明窗口回退命中；都不是功能全通过。`NO HOOKS` / `CONFLICT` / `SUSPEND` 表示没有启用或已停止。
- 如果没有 `TRACK` / `WORLD`，不要叠加更多补丁强制生效：这表示当前窗口结构/方向/版本未满足保护条件。

## 诊断：实时看触摸与手势（alpha9-10，纯只读）

想直接看清"手指移动灵动岛时系统内部在处理什么"，而不是靠日志反推时，在设备上创建空文件 `/var/mobile/Library/Preferences/MangoUpsideDownWorld.trace`（与 `.disabled` 同目录、同建法：Filza 新建空文件或 SSH `touch`；`access()` 检查只看文件是否存在，不看内容或类型，Filza 里"新建"不可用时复制同目录任意已有文件再粘贴重命名同样有效）。约 0.25 秒内生效，不需要 respring；删除该文件即关闭，同样不需要 respring。

开启后屏幕上会出现一个可拖动的小悬浮球，上面的数字是已捕获的记录条数：

- **拖动**悬浮球可以把它挪到不挡住灵动岛的位置。
- **点一下**展开成一块可滚动的深色面板，直接在屏幕上看完整历史，不用再去翻日志文件；再点一下收起。
- 面板展开时，**长按面板**会把当前显示的全部历史一次性复制到系统剪切板（面板会闪一下白色确认已复制），可以直接粘贴发出去，不用手动选字。
- 同时也仍然写入 `/var/mobile/Library/Logs/MangoUpsideDownWorld.log`（多一份留档，不需要就不用管）。

记录的内容是 `TOUCH` 行：

```
TOUCH phase=Moved window={187.3,42.1} fixed={187.3,769.9} view=SomeClass recognizers=UIPanGestureRecognizer(state=Changed,touches=1),...
```

- `window`/`fixed`：同一个触点在窗口坐标系和屏幕固定坐标系下的位置，两者不同正是 EVIDENCE.md 里"读数者按固定坐标系判断"这条推理的直接体现。
- `view`：这次触摸命中的视图的真实类名。
- `recognizers`：沿这个视图父链收集到的**全部**手势识别器，每个都带真实运行时类名（不是猜的名字）、`state`、`numberOfTouches`。如果处理拖动的是某个重写了 `translationInView:`/`velocityInView:` 的私有子类，它的类名会直接出现在这里——不需要再靠"有没有 GESTURE 行"去反推。
- 已有的 `GESTURE` 行现在也带上了 `class=`，同样是识别器的真实运行时类名，一并显示在悬浮面板里。

全程只读：`sendEvent:` 的 hook 在调用原始实现**之后**才读取，不改变命中测试、分发顺序或任何返回值；悬浮球本身是一个独立的 `UIWindow`，World 从不把它登记为 Root，因此本文件其它几何/手势修正逻辑都不会作用到它，与修复逻辑完全独立。悬浮面板最多保留最近 300 条，文件日志仍受现有 512KB 轮转限制。

alpha11 额外新增两类日志，装上后自动记一次/持续记录，不需要额外开关：

- `CLASSDUMP <类名> methods=...`：装上时记一次，列出 `SBSystemApertureLongPressGestureRecognizer` 和 `_SAUIPortalView` 各自真正定义（不是继承）的全部方法名。
- `LPROBE api=... point={x,y} state=...`：只要这个真实的手势类调用了 `locationInView:` 或 `locationOfTouch:inView:`（`UIGestureRecognizer` 所有子类都有的公开取位置方法），就会记一条，同时也会出现在悬浮面板里。**如果拖动灵动岛时这一行完全不出现**，说明这个类读位置根本不走这两个方法（很可能是重写了 `touchesMoved:` 之类，直接用原始 `UITouch` 坐标）——这本身就是有价值的结果，不是探测失败。

## 编译

工程使用 RootHide Theos、iOS 16.5 SDK、Apple Clang（macOS），`ARCHS=arm64e`，`THEOS_PACKAGE_SCHEME=roothide`。运行 `make package FINALPACKAGE=1`。CI 校验 SDK 哈希、拒绝 incompatible arm64e ABI 警告并审查 deb 内容。

GitHub Actions 构建产物包含 deb、编译日志、load commands 和 SHA256。源码在本分支；不包含付费 Mango 二进制。更多原理与已知不足见 EVIDENCE.md。
