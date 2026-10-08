# Beta9.5 方向模块适配

Suite `1.2.0~beta9.5`，Mango `1.0-Beta9-1`，iOS 16.5，Dopamine RootHide，arm64e。用户提供的原包 SHA256 为 `4826d2e73c59f05e0ff529da1e7db47e494ebfc89498fd3c8280917268e2dadd`。

本版回归缓解恢复 Beta9.3 的 Split 根视图和 World/WorldPlacement 路径。Beta9.4 对左右容器和菜单的独立半转、布局挂钩、窗口终点替换已撤下。历史根视图日志仅证明补偿曾施加，不能证明左右资源库和底部设置的位置、方向与触摸已正确。

World 编译 World.m、WorldPlacement.m、XiaoMang.m；Split 编译 Split.m、LauncherSurfaces.m。后者仅为已核对 ViewController 六个 getter 和已呈现菜单提供只读观察；不安装任何资源库／菜单布局挂钩，不写变换和坐标。watchPickerView/Right getter 来源和 ABI 已从原始 MangoHello 核对，详见 repair-surface-audit.json。

MangoPillElement.handlePanGesture: 和 Hello 的 aperture resize-pan 入口仍经运行时身份和签名核对；挂钩只用于透传和记录。MSRunObservedPan 原样传入 controller、selector、recognizer，执行原方法一次。无全局 UIPanGestureRecognizer 查询挂钩，无位移或速度补偿，不吞原始异常。第7项明确暂停。

镜像身份沿用 Beta9Identity.h 的 Hello/Panda UUID 及加载器 Rendering 校验。原生方向 getter、授权和原始二进制没有修改。小芒路径未作新增改写，范围见 [XIAOMANG.md](XIAOMANG.md)。

CI 执行生产观察器、既有方向／放置／所有权／首次施加回归和小芒检查，并重新编译 arm64e 代码。数学和宿主测试不能代替 UIKit 动画、触摸、SpringBoard 稳定性与真实调用栈。
