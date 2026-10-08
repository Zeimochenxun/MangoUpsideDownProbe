# Beta9.4 调试记录与提取

在设置 → Mango 整合 → 调试日志与一键提取中点击开始记录，复现后点击提取。无需运行终端工具。
默认关闭，记录会话持续20分钟，可再次点击开始重新计时。每模块256KB、每秒最多8条。日志保存在 RootHide 映射的 /var/mobile/Library/Logs/MangoSuiteDiagnostics，模块名为 Idle、Glass、World、Split。
导出通过系统分享页面生成有界文本，记录开关、会话、尺寸、物理坐标、方向、变换所有权、手势补偿和采色接口状态。不会导出通知文字、媒体内容、完整设置域或截图。
Glass 中的 display-pixels 表示从可用的系统屏幕接口取像，springboard-window-pixels 表示窗口快照回退，不能证明前台 App 已被捕获。采集失败会记录不可用并移除采色效果。所有像素仅在一次采样的内存中使用。
底层读写拒绝符号链接和非常规文件，文件只由手机 mobile 用户读写。现有 capture-runtime.sh 作为手动备用提取工具保留。
日志只提供排查证据；最终显示与触摸结果仍需要手机上的观察。

## Beta9.4 新记录

`NOTIFICATION hooks` 应列出通知生命周期安装位，`notification=1 host=...` 表示结构化通知已识别；不记录通知正文。`PAN install` 显示 query／resize／pill 各入口状态，`PAN ended` 显示最终回调，`PAN query` 提供 rawY／effectiveY 和按坐标决定的 flip。`SURFACE role` 区分左右容器、左右资源库和 bottom-split-settings，提供位置、大小、继承状态、所有权及变换。`Glass` 按每层记录 localContour、native-mask／local-rounded、haloParent=window、halo、厚度及当前轮廓。没有相应事件时请保留日志；安装成功或矩阵正确不代表可见效果与最终动作正确。
