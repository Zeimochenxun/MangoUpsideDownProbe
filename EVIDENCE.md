# MangoUpsideDownWorld 0.1.0-alpha1：证据与边界

这是本次新实现，不是从关联对话中取回的既有 World 源码，也不是给 Fix alpha2 改名。

## 已证实的输入

- Mango 镜像 UUID：67C0D7C2-4487-3FD2-9535-067745AE4B8F。
- Mango 静态分析：DecoratedAppSceneView 的类方法 mango_currentInterfaceOrientation（原镜像 IMP 0x721d0）；本地通知 MangoInterfaceOrientationDidChange。仅读取方向，不更改 Mango 的方向报告。
- 真机日志：MangoUpsideDownProbe(3).log，SHA256 bdeca97908ca702dbfc3d4d6497f1890f91bab9998fec229186577eea07082d8。
- 日志 2441–2450 行的真实父链：Mango host → SAUIElementView → UIView → _SBSystemApertureContainerViewContentView → UIView → SBSystemApertureContainerView → 三层 SBFTouchPassThroughView → SBSystemApertureWindow。
- 内容层已带 180° transform；三层触摸穿透视图仍为 identity；窗口有 25/24 缩放。
- 最外层触摸穿透视图固定坐标大小约 375×811.80556，屏幕是 375×812。不能忽略窗口缩放或直接写死 812 点的父坐标。
- 用户纠正：只有通知视觉正常，触摸仍不正常，其他形态视觉和触摸也异常。因此不采用“展开已修复”的旧结论。

## 新方案（实验，未真机证明）

World 选择 SBSystemApertureWindow 的直接子 SBFTouchPassThroughView；要求它覆盖全屏且含真实内容层。对这个完整根视图围绕固定屏幕中心作半周旋转。该旋转覆盖其所有子元素和父子坐标转换，不以透明 Mango host 是否出现为前提。

在整体旋转之前，检查每个 _SBSystemApertureContainerViewContentView 的未补丁基向量：若已倒置，则抵消其内部半周旋转，保留缩放和位移；若本来正向，则不改。这样整个屏幕倒过来使用时，内容理论上保持可读。过渡角度、非仿射层级、嵌套内容层或不是全屏的根视图均跳过。

窗口 hitTest / pointInside 保留原结果优先。在原结果为空或窗口自身时，使用真实 UIView 坐标转换询问已变换根视图的原生 hitTest。仅接纳仍可见、可交互的真实后代；不伪造触摸事件、不交换 UITouch 坐标、不直接调用业务按钮。未命中时仍穿透。此补偿不能保证 BackBoard 向窗口派发触摸；若事件被更上游裁掉，本版不会解决。

正常竖屏、横屏恢复本补丁拥有的 transform。不改 frame/bounds/center、safeAreaInsets 或原始 Mango 文件。hook 的 layoutSubviews、geometry setter、hitTest:withEvent:、pointInside:withEvent: 均为 UIView 公共方法，先核对运行时签名；没有声称这些是 Mango 自定义方法。

## 保留风险

1. 模型坐标数学验证不能证明 presentation layer 动画、手势捕获或自定义系统点击区域正确。系统动画可能出现过渡闪动；4 Hz 校正不是逐帧动画同步。
2. 未重写 safe area。内部布局仍由系统/Mango计算；展开间距和展开方向必须真机核验。
3. 未取得其他实时形态的完整日志；不承诺独立 fallback UIWindow、窗口外图层或独立浮层得到修正。
4. 直接 CALayer 写入冲突时不猜测新基线，停止该实例；需 respring 清理。父布局读取变换后的 frame 仍有反馈风险。
5. 同一系统 aperture 根里的其他元素也跟随倒置，这是整体方案的作用范围。只在已核对 UUID 和 iOS 16.5 下启用。
6. 没有倒置插件本身的二进制，不能确认其是否修改 compositor / HID 或仅修改 UIKit。本版没有 backboardd 注入。

测试覆盖：局部语法检查；1000 组仿射半周变换及逆变换；日志中的缩放/非对称中心案例；重复旋转抵消；非有限数值拒绝；CI 将检查真实 deb 的 arm64e、RootHide 链接、签名数据、SpringBoard 注入过滤及仅含两个 payload 文件。均不等同于真机验证。
