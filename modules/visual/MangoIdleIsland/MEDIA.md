# Beta8.3 媒体交接

Idle 仍只补闲置玻璃，不创建标题、封面、频谱或系统媒体 activity。

新逻辑每秒至多读取一次实际播放状态。播放中，或原生 `MRUActivityNowPlayingView` / `MRUSessionNowPlayingView` 已挂到对应岛的子树中，即释放 Idle 自身的玻璃。原生媒体尚在 `alpha=0` / `hidden` 的揭示阶段也获得优先权。原 layout 回调执行前完成这个释放；普通闲置 layout 不会反复移除和插入。稳定玻璃不再反复调用相同 frame、radius、alpha、hidden setter。

原版二进制与授权逻辑均未修改。没有把“发现一个玻璃实例”作为媒体正在播放的证据。

`tests/media-abi-evidence.json` 记录从供应的原版 MangoPanda 读取的证据：0x4567c0 解码 `MRMediaRemoteGetNowPlayingApplicationIsPlaying`；0x4573b0–0x4573c0 使用 main queue 和完成块；block descriptor 0x9c6218 的 signature 为 `v12@?0B8`，即 void / BOOL 完成回调。可在原审查目录仍存在时复验：

```
python modules/visual/tests/audit_media_readonly.py MangoPanda --verify-media-abi
```

现有 `test_idle_handoff.py --require-clang` 追加直接执行生产 helper 和 Layout 函数体，覆盖先于原 layout 的释放、播放状态释放、透明且隐藏的原生媒体根视图、稳定时不重复写 frame。三个有意引入的回归负对照必须失败。测试使用 Objective-C 属性 stub，不能代替 UIKit 动画与手机验证。

证据尚不能证明 Idle 的原玻璃造成了用户报告的媒体缺失。因此这次交付可确认的是媒体所有权与 layout 互操作修正，不能声称已定位原缺失的唯一根因或已在 iPhone 13 mini 上通过。
