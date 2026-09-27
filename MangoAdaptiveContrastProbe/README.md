# MangoAdaptiveContrastProbe 0.1.0

适用：iOS 16.5、Dopamine RootHide、Mango Beta7-1。它是临时只读探针，独立于已验证边缘光的 MangoIdleIsland 1.1.5；不会调整滤镜、窗口、触摸或任何偏好。仅注入 SpringBoard，十分钟后自动停止采样。

## 为什么需要这一步

目标是让灵动岛像底部小横条一样在明暗画面中保持可见，且空闲、通知、音乐及展开状态都适配。二进制已证实 SpringBoard 使用 `MGLiveBackdropView` 的 `go.mangoos.island` 滤镜，backboardd 有对应组的颜色参数；但是否每种状态都存在同样的活动玻璃、怎样与内容层交接，需要一轮设备对照。本探针只确认状态覆盖，不推断实际背景像素亮度。

## 单次测试

1. 保持 MangoIdleIsland 1.1.5，不要安装更旧版本；安装本探针，Respring。
2. 十分钟内按顺序各停留约 15 秒：空闲 → 音乐收起 → 音乐展开 → 通知收起 → 通知展开 → 返回空闲。尽可能分别在明、暗背景上观察岛体和文字是否清晰。
3. 在 Filza 打开 `/var/mobile/Library/Logs/MangoAdaptiveContrastProbe/Probe.log`。每次 Respring 生成新的 Probe.log，上一轮移为 Previous.log；日志只记岛体玻璃、滤镜类、尺寸、可见性、内容层和方向，不采集通知文字或图像。完成后卸载本探针，不影响 MangoIdleIsland。

如果不能触发某种展开状态，记录已经成功触发的状态即可。日志的 `trait` 是系统明暗外观，并非背景像素明暗；本探针不会宣称观察到“真正背景亮度”。

## 恢复

若 SpringBoard 异常，重启设备，在 Dopamine 禁用 tweak 注入后重新越狱，用 Sileo 卸载 `com.chenxun.mangoadaptivecontrastprobe`，然后恢复注入。不要删除 Mango 或 MangoIdleIsland。也可在日志目录创建空文件 `DISABLED` 停止后续采样。
