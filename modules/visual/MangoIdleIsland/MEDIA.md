# Beta8.4 媒体交接回归修复

用户在 iPhone 13 mini / iOS 16.5 / Dopamine RootHide 的反馈是：Beta8.2 播放媒体没有岛内内容但玻璃仍在；Beta8.3 播放时整岛消失。Beta8.3 的新增代码存在直接解释消失的路径：全局播放状态，或同窗口附着的 `MRUActivityNowPlayingView` / `MRUSessionNowPlayingView`，会在原 layout 前移除 Idle 的唯一补底，并在 Eligibility 中直接返回 `media`。该路径没有要求原生活动可见，隐藏、透明和零尺寸占位也触发。

Beta8.4 删除该播放查询、MRU 类存在判定和提前释放路径，恢复 Beta8.2 已有的原生 `SAUIElementView` / 原 Mango Island glass presentation 透明度判定。原 layout 完成后，在既有的最多 256 个节点的子树扫描中评估这些活动层。MRU 根即使非空且 alpha=1，也不能独自证明岛已出现实际原生活动。稳定紧凑岛没有可见活动时保持 Idle 玻璃；原生活动淡入/淡出仍使用 `1 - activity` 补底，activity 达到 0.995 后释放，原有展开/长按几何排除规则继续适用。Beta8.3 的稳定 frame、radius、alpha、hidden 防重复写入优化保留。

Idle 只补闲置玻璃，不创建标题、封面、频谱或系统媒体 activity。原版二进制与授权逻辑均未修改。此修复撤销了未经真机证实的接管假设，不能据此宣称已修好 Beta8.2 的媒体内容缺失。

`tests/media-abi-evidence.json` 保留原版 MangoPanda 的 MediaRemote ABI 读取记录。ABI 可用只能证明查询调用形式，不能证明播放状态会产生系统活动，也不能证明 Idle 玻璃妨碍原生媒体；Beta8.4 不再使用该查询。MRU 类 hook 证据也不能证明根容器透明度代表实际活动像素，因此不再作为 Idle 的媒体接管信号。

`test_idle_handoff.py --require-clang` 直接提取并执行当前生产 `Eligibility`、`Update`、`Layout` 和 helpers，覆盖播放而无活动、两种 MRU 根的隐藏/透明/零尺寸/不透明空占位、媒体容器下的可见原生 element/glass、隐藏祖先、presentation 淡入淡出、完整可见接管、原 layout 完成后判断及稳定 setter 防重写。五个负对照分别重新引入全局播放判定、隐藏占位判定、重复 frame 写入、提前拆除和双算透明度，必须失败。原 handoff 的双算透明度及只看 model 几何负对照也保留。

测试使用 Objective-C 属性 stub，不能代替 UIKit 动画与手机验证。Windows 本地只能验证生产函数提取和负对照构造；实际执行需要 macOS clang。尚未完成 iPhone 13 mini 真机复测，不将代码路径解释等同于实机根因已完全确认。
