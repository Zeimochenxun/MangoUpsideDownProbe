# 证据与实现说明

## 输入与可信度

本工程依据用户上传的原始二进制分析及真机日志，不根据 Mango 名称猜测私有类。静态地址均是给定镜像内的 unslid VM 地址，**代码未使用任何硬编码函数地址**。

| 标识 | 来源 | 本版用途 |
|---|---|---|
| `MangoPillElement` | mango.dylib 的 ObjC 元数据 | 唯一 Mango hook 目标类 |
| `layoutHostContainerViewDidLayoutSubviews:` | Mango IMP `0xe4a5c`，日志有真实调用 | 获取 host；原方法先执行且仅调用一次 |
| `DecoratedAppSceneView` / `+mango_currentInterfaceOrientation` | IMP `0x721d0` | 读取 Mango 已缓存的方向；检查返回类型，不修改方向 |
| `MangoInterfaceOrientationDidChange` | Mango 本地 NSNotificationCenter 发布，原探针已验证 | 回转时主动撤销/重算，不依赖新的 Mango layout |
| `SBSystemApertureContainerView` | 最终真机父链 depth 5 | 平移的唯一候选容器类；必须由 host 关联到具体实例 |
| `_SBSystemApertureContainerViewContentView` | 最终真机父链 depth 3 | 检查固定坐标中的基向量确实已倒转 |
| `SBSystemApertureWindow` | 最终真机父链 depth 9 | 限制窗口范围 |
| `layoutSubviews`、`setFrame:`、`setBounds:`、`setCenter:`、`setTransform:`、`didMoveToWindow` | UIView 公共方法 | 在上述容器类上检查实际签名后挂钩；没有声称 Mango 自定义实现了这些方法 |
| `hitTest:withEvent:`、`pointInside:withEvent:` | UIView / UIWindow 公共方法 | alpha2 只读探针；在容器类和 aperture 窗口类上检查签名后挂钩，原值原样返回 |

`MUDFFixState`、`MUDFPlan`、`MUDFPendingHost` 等均为本补丁新定义的实现名称。

Mango UUID：`67C0D7C2-4487-3FD2-9535-067745AE4B8F`。

最终日志 SHA-256：

```text
bdeca97908ca702dbfc3d4d6497f1890f91bab9998fec229186577eea07082d8
```

`MangoUpsideDownProbe(3).log` 与交接包 `04_final_parent_chain.log` 内容完全相同。13 组父链的 Mango host alpha 均为 0；容器和内容上层可为 1，因此不能把 host 的透明状态推断成整个系统岛不可见。

## 修正交接报告中的简化

交接报告称容器 y 一直约 10～11；原始日志也有 y=4 和 y≈8.67。更关键的是，那些值是父视图坐标，不是屏幕坐标。window 具有 `25/24≈1.0416667` 倍缩放，某些父视图另有 y≈24.33 的偏移；动画采样中还出现额外缩放。

典型样本转换后的容器矩形为：

```text
fixed x ≈ 87.152778
fixed y ≈ 37.152778
fixed width = 196.875
fixed height ≈ 38.194444
fixed screen height = 812
```

对侧目标 minY≈736.652778，固定坐标差 699.5，换回该父坐标的位移为 671.52。代码动态计算这些量，**没有写死这些机型数值**。

报告中的“当前源码”与标为 INCOMPLETE 的历史文件相同；本工程没有把其文件名当作编译证明，而是使用已核对的 helper 思路和实际证据重新实现 Fix。

## 坐标算法

令固定屏幕矩形为 S，未施加本补丁位移时的容器矩形为 R：

```text
target.minY = S.minY + S.maxY - R.maxY
fixedDeltaY = target.minY - R.minY
```

通过父视图的三个转换点 `(0,0)`、`(1,0)`、`(0,1)` 得到父坐标到固定坐标的二维线性映射 A。父坐标位移为 `A⁻¹ × (0,fixedDeltaY)`，只加到外层容器 baseline transform 的 tx、ty。保留原 a、b、c、d、尺寸和水平位置。

重复计算时，先从当前固定矩形中扣除**自己此前拥有的平移**，得到 baseline；不会对已经移动过的矩形再做一次镜像。

只接受：方向 2、Mango host 仍在已识别容器下、主屏幕 aperture 窗口、二维仿射且无未知 sublayerTransform、内容固定基向量为 180°、baseline 位于屏幕上半部。已在下半部或异常几何时不再次移动。

## 布局与恢复策略

对已跟踪实例，容器的公共 geometry setter 和 layout 被调用时：

1. 撤销仍能精确确认属于本工程的 transform 平移。
2. 原方法调用一次，参数不变；嵌套 setter 通过深度计数合并。
3. 原方法返回后，以新的系统模型几何重新计算补偿。

方向通知和 4 Hz 主队列定时器负责回转恢复、弱 host 脱离检测与禁用标记检查。定时器不是动画帧驱动器。对未关联实例，以及没有本补丁位移的正常竖屏/横屏，不写几何属性。

首次只有在 Mango 的真实 host 回调出现后才建立关联；不做全局窗口扫描。没有修改 UIView 或 UIWindow 基类的实现，只在实际容器子类挂钩。这仍属于系统私有容器兼容方案，不是纯 Mango 方法内部的局部调整。

## alpha2：待挂载 host 与只读触摸探针

alpha1 真机结果：展开态位置已修好；紧凑态/媒体小岛未移动；触摸不跟随。

### 生命周期

alpha1 在 Mango 回调那一刻要求 host 已经位于 aperture 容器之下且容器已在 `SBSystemApertureWindow` 中，否则直接返回。日志显示紧凑态与媒体小岛的 host 在回调时 `window` 为 `nil`，因此被丢弃——这是紧凑态没有被修复的原因，不是坐标算法的问题。

alpha2 把这类 host 以**弱引用**入队，并在三个时机复查：主队列下一轮、Mango 方向通知、以及既有的 4 Hz 定时器。复查一旦成功，走的是与展开态**完全相同**的关联和计算路径，没有为紧凑态另写一套几何。

边界：队列去重、上限 64 条、单条 TTL 30 秒；超时即释放并记 `PENDING … expired`。弱引用保证被丢弃的 host 不会因为排队而延寿。复查函数遍历队列快照、按对象标识移除，且带重入标记，因为关联过程会触发布局、布局可能再次进入 Mango 回调。

**坐标算法在 alpha2 中完全未改**：`Geometry.h` 与 alpha1 逐字节相同，因此既有的几何测试仍然是对生产代码的有效检查。

### 触摸诊断

alpha1 只证明了**模型几何**到位（`APPLY` 的 post-write 检查），没有证明命中测试跟随。alpha2 不猜原因，先加只读探针：

- 容器与 aperture 窗口的 `hitTest:withEvent:`、`pointInside:withEvent:`：记录后**原值返回**。
- 祖先链是否接受同一点：用公共 `pointInside:withEvent:` 逐层询问。`SBFTouchPassThroughView` 是已证据化父链中的一层，也是 SpringBoard 共享基类，因此选择**查询**而非挂钩它。
- 这些自发查询会重入被挂钩的 `pointInside:`，故用重入标记抑制嵌套记录，避免把自己的提问记成真实事件。
- 频率：每容器首次必记，随后约 0.5 秒一次；窗口级探针仅在该窗口确有已平移容器时才记录。

探针要区分三种原因：事件未下降到被移动的容器（`reachedTrackedContainer=0`）、窗口在该点即拒绝（`REJECTED`）、容器自报命中区域与 `bounds` 不符（`DISAGREES`）。**本版据此不做任何修正**；先取证再决定，是为了避免盲目注入事件平移。

如果其他代码绕开受监控的 setter，直接改 CALayer transform，导致现值与本工程记录的不一致，本版会放弃覆盖并暂停该实例。它不能保证恢复未知变化；通过 respring 清理，不能假装安全地猜回基线。

## 尚未解决的具体风险

- 系统父布局可能读取已经平移后的 `frame` 再反推布局。类内 setter 前撤销能覆盖常见“系统给新 frame”路径，但没有证明所有父布局都不读取修改后的 frame。
- 动画中的 presentation layer 和父变换未逐帧补偿；系统改变尺寸的动画可能短暂闪回、跳动或路径不自然。没有移除系统动画来掩盖这一点。
- 普通视图变换参与坐标换算，但 `SBFTouchPassThroughView` 或系统窗口可能有自定义交互区域。坐标正确不能证明点击必然跟随。**alpha1 真机已确认触摸确实不跟随；alpha2 只增加诊断，未修复。**
- 不改变 safeAreaInsets。即使位置到达对侧，也仍需观察展开内容是否沿用错误的边缘间距。
- 本版不额外修复水平居中，不覆盖 fallback UIWindow，不承诺所有音乐/计时器容器都能经 Mango host 发现。alpha2 的排队复查扩大了能被发现的 host，但无法覆盖根本不经 Mango 回调出现的容器。
- 排队复查依赖 host 最终挂到已识别的 aperture 容器下。若紧凑态实际走另一条容器路径，日志会显示 `PENDING … expired`，而不是被静默忽略——但本版不会因此自动改用其他容器。
- 探针会在触摸路径上增加日志与祖先查询。已做限频，但它仍是诊断代码；只要位置修复，可用 `.noprobe` 标记关闭。
- 若主线程卡住，运行时禁用定时器也无法执行，必须使用外部卸载/关闭注入恢复。

因此这是 **0.2.0-alpha2 的可审查实验实现**，而不是已经完成全场景兼容验证的成品。位置修复在展开态已有真机证据，紧凑态覆盖与触摸行为仍待本版日志判定。

参考：[Apple 视图与坐标变换](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewPG_iPhoneOS/CreatingViews/CreatingViews.html)、[RootHide 开发说明](https://github.com/roothide/Developer)、[Theos 构建限制](https://theos.dev/docs/rootless)。
