# Beta9.5 调试日志

进入设置 → Mango 整合 → 调试日志与一键提取，点击开始／重新开始记录；会话20分钟，每模块最多256KB。复现后点击提取全部相关日志，系统分享页保存 `.txt`。不保存通知文字、截图或封面。

Beta9.5 是回归缓解包：通知方向补偿已停用，原偏好仅保留；左右资源库和底部设置没有新增布局挂钩或独立旋转。

- World：`PAN install query=0 correction=paused`；`PAN native-begin/native-return` 的同一 seq 用于判断原入口是否返回。不再有 rawY/effectiveY 改写记录。记录缺失可能是速率限制或入口未安装，不能据此排除崩溃。
- Split：`SURFACE observer=1 writes=0 hooks=0`，role 区分左／右启动器、普通资源库、watchPickerView/Right 蜂巢资源库、bottom-split-settings。记录模型位置、呈现动画位置、变换和裁剪。动画变化最多每视图4次／秒，稳定时约3秒一次，日志还有每翻译单元每秒8条限制。
- Glass：每层轮廓、halo、实际粗细与采色来源；`clipOwned=0` 表示原生裁剪层未被本版替换。NOTIFICATION 只记录结构化存在状态和宿主。
- Idle：原有活动／静止及玻璃交接记录。

若进入安全模式，先提取已有会话；不要先重新开始记录而过滤掉前一会话。附上对应时间的 SpringBoard `.ips`／`.crash`，并注明左侧滑入、右侧蜂巢或通知上滑的触发步骤。回调未返回并不单独证明崩溃位置，需与崩溃线程和镜像信息对照。

附带 capture-runtime.sh 只做立即快照，不注入、不改偏好、不重启进程。日志矩阵、轮廓来源或采色可用标记都不能替代真机观察。
