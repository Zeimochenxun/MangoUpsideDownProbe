# IdleIsland 1.1.9.2~alpha2 针对性检查

在候选 `MangoIdleIsland` 目录运行：

```sh
python3 tests/test_idle_conservative.py
```

Windows 可使用 `python`。Python 测试不依赖额外包，从实际 `Tweak.m` 提取三个 helper 的条件、取值表达式和循环，验证淡入/淡出、祖先透明度、hidden、无 presentation 回退、普通按压 transform/位移，以及原有内容 opacity fallback。新增通知清除回归：模型125，presentation按160→143→129→125.8→125返回、native opacity=0，从紧凑143起恢复背衬；presentation129、native opacity=0.75时背衬为0.25；模型或presentation为150×44时仍不参与。

`fixtures/idle119_helpers.m` 保存实际 1.1.9 的两个 helper；`fixtures/idle_alpha1_helpers.m` 保存实际 alpha1 的三个 helper。测试确认原1.1.9在淡出与展开presentation边界用例失败，alpha1在紧凑回归用例失败，alpha2通过。

源范围检查必须使用固定的 `../inputs/Tweak.alpha1.m`：原始字节SHA-256为 `ca17e881eb6a7dc4ba3f9e3cbb4638f143e1536e67e16f70eb9331b6f8e13ce5`，UTF-8标准换行SHA-256为 `12703c541307e5b3cf07c66ee0f59c695a1ad597e5ea080a3d8cbeded2ef3441`。测试只逆转alpha2几何门限、版本和诊断改动，必须逐字回到该输入，保证EffectiveOpacity、Visible、activity MAX、hook、Timer与其他代码不变。CI需保留输入原有CRLF字节，不要自动转换换行。

macOS 有 `clang` 时，同一入口将候选、alpha1、原1.1.9的未经改写的实际helper分别插入同一个 `idle_handoff_harness.m`，链接Foundation/CoreGraphics并编译执行。派生背衬检查使用候选实际Update里的need/background表达式；不是完整UIKit挂载过程。要求退出码依次为候选0、alpha1负对照1、原1.1.9负对照1。CI可用 `--require-clang` 强制要求这一步通过，缺少运行条件时明确失败。该property stub不使用UIKit，不代表Core Animation的真实渲染或时序。

必须另做真机观察：通知出现后上划清除；音乐锁屏活动；活动玻璃淡入/淡出；长按展开后回弹；快速多次按压；超过1秒的过渡。核对清除通知后的短暂空白是否消失，紧凑回弹尾段是否出现位置或双层问题。当前保留内容opacity fallback与500 ms timer，未修复内容/裁剪可见性与长动画采样问题。新增 `[STATE]` 字段可区分presentation几何、元素/玻璃透明度与Idle实际挂载/隐藏状态，但保持原有只在state变化时记录的频率。
