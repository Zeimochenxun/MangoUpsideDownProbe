# Mango Beta7 空闲灵动岛静态证据

输入：用户提供 tweak-20260925-021720 2(1).zip，内含 byg.iosios.net.mango_1.0-Beta7-1_iphoneos-arm64e.deb。仅解包分析；不重新发布 Mango 或依赖包。

模块 mangoos.dylib SHA-256：b518c70628337ebe5756c9156859c5d8cde8e426e968d4a32d2ddf2ef09e2a7b。
以下地址是该 Mach-O 的未滑移虚拟地址，不是设备上的绝对指针。没有使用这些地址进行修改。

## 已证实

1. `0x49334` 是一段安装显示 Hook 的函数。实际引用 `SAUIElementView`、`SBSystemApertureSceneElement`、`_SBGainMapView`、`_SBSystemApertureMagiciansCurtainView`、`SBFTouchPassThroughView`、`SBSystemApertureViewController`、`SBSystemApertureWindow` 等名称；部分名称存放在常量数组内。
2. 该函数将 `layoutSubviews` 的替换实现设为 `0x497cc`。该实现先调用保存的原实现，再读取宿主 bounds；`0x49840–0x49848` 调用 CGRectIsEmpty，为空则转向清理/返回路径，跳过后续玻璃创建。
3. `0x49890–0x498b8` 构建真实类 `MGLiveBackdropView`，使用真实 selector `initWithFrame:groupName:filterType:`，参数字符串为 `Island` 和 `go.mangoos.island`。`0x498f0` 将玻璃插入宿主 subview index 0。
4. `0x49abc–0x49ac8` 将显示决策结果取反后传给玻璃视图的 `setHidden:`。显示决策不是单纯强制常开；相关设置和 layoutMode 参与路径。
5. `0x49978–0x499e8` 在条件满足时找含 GainMap 的子视图并 removeFromSuperview，找 Curtain 子视图并 setHidden:YES。
6. `_SBGainMapView setHidden:` 的替换实现 `0x4aa60`：先转发原调用，若请求显示且条件函数满足，则再次隐藏并在有父视图时移除（`0x4aaa0–0x4aae4`）。不能据此假定所有状态下都会移除。
7. `_SBSystemApertureMagiciansCurtainView setHidden:` 的替换实现 `0x4aba4`：在条件满足时将显示请求重新设为隐藏（`0x4abe4–0x4abfc`）。
8. `setLayoutMode:reason:` 的替换实现 `0x4a680` 区分 mode 0 和 3，调用 `0x4ccd0` 更新布局状态；后者在相关选项启用时识别 mode 3，以及兼容模式下的 mode 2。这里的 mode 是布局枚举，不是 UIInterfaceOrientation，不能混淆。

## 推测与未确认

高价值假设：液态玻璃依赖系统的活动内容宿主，而原生黑色背景又被清理，因此完全空闲时没有任何可见胶囊。静态代码支持这个解释，但不能证明本机空闲时宿主被销毁、隐藏还是缩成零尺寸。用户所说“灵动岛不存在”是视觉观察，不等于运行时对象一定不存在。

现在不能把某个 layoutMode 数字强制改成展开状态，否则可能改变内容布局和触摸；也不能全局解除 hidden，否则可能把已被系统正常隐藏的界面一起显示出来。

本轮不会分析、改写或绕过授权函数。玻璃存在权限判断不代表该判断导致用户的空闲消失问题；这些入口不作为常驻修复点。

探针用于把上述未确认项变成运行时证据；常驻修复仍需这一步真机结果。
