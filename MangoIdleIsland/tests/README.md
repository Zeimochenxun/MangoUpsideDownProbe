# IdleIsland 1.1.9.1~alpha1 针对性检查

在候选 `MangoIdleIsland` 目录运行：

```sh
python3 tests/test_idle_conservative.py
```

Windows 可使用 `python`。Python 测试不依赖额外包，从实际 `Tweak.m` 提取三个 helper 的条件、取值表达式和循环，验证淡入/淡出、祖先透明度、hidden、无 presentation 回退、模型/presentation 尺寸差异、普通按压 transform/位移，以及原有内容 opacity fallback。完整 source 反向还原后的 SHA-256 必须等于 1.1.9 基准，防止授权范围外的逻辑漂移。

`fixtures/idle119_helpers.m` 保存实际 1.1.9 的两个 helper；测试核对它与反向还原的基准源码一致，并确认旧代码对“淡出未结束”和“回弹未结束”用例失败、候选通过。macOS 编译执行时也对同一 harness 运行基准负对照，要求其以预期失败码退出。

macOS 有 `clang` 时，同一入口还会将三个未经改写的实际 helper 插入 `idle_handoff_harness.m` 的轻量 Objective-C property stub 中，编译并执行。CI 可用 `--require-clang` 强制要求这一步通过，缺少运行条件时明确失败。该 stub 不使用 UIKit，不代表 Core Animation 的真实渲染或时序。

必须另做真机观察：音乐锁屏活动；活动玻璃淡入/淡出；长按展开后回弹；快速多次按压；超过 1 秒的过渡。核对 Idle 没有提前恢复导致双层，也没有因为几何 guard 出现闪黑。当前保留内容 opacity fallback 与 500 ms timer，因此并未修复“内容先出现”与长动画采样问题。
