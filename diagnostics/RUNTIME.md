# Beta9.6 日志与崩溃报告

设置 → Mango 整合 → 调试日志与一键提取。

优先点击“提取最近 SpringBoard 崩溃报告与日志”，取得此前上滑时刻对应的 .ips／.crash 和已有会话。不必反复触发，也不要先重开会话。最多复制3份合格完整报告，每份2MB；只读同用户普通文件并确认 SpringBoard 进程，原文件不改。候选路径、权限、扫描和读取上限可能使导出为空，空结果不能排除崩溃。

保存已有记录后，再开始／重新开始记录。即使整合修复停用，Foundation 启动观察器仍可记录约两秒内的实际 loaded image 状态。每会话20分钟、每模块256KB；关闭记录后停止写入。

Startup 字段：compiled-loader 实际编译版本；plannedMask 启动加载计划；isolationAtStartup 启动时隔离状态；isolationRequested 当前保存状态；suiteImagesCurrently 当前 SpringBoard dyld 中整合目录模块位图（Idle=1、Adaptive=2、World=4、Split=8）。repairImagesAnyPath 另记录任何路径的四个同名修复模块，legacyOrientationImage 标记旧方向／探针镜像。镜像存在不代表其挂钩已安装，列表最多64项且注明截断。

成功的本次隔离记录应为 Beta9.6、plannedMask=0、isolationAtStartup=1、suiteImagesCurrently=0、repairImagesAnyPath=0、legacyOrientationImage=0。开关已改但旧模块仍存在时，先核对用户空间重启；SpringBoard 记录不能证明 backboardd 旧进程已经退出。更改隔离开关后需在多巴胺中重新启动用户空间。

隔离下 Idle／Glass／World／Split 模块不加载，缺少这些新记录是预期。Mango 原版和其它注入仍存在，安全模式根因需真实报告的崩溃线程与镜像对照。启动记录和没有复现均不能视为七项问题已修复。

附带 shell 工具仍仅采集已有日志快照，不注入、不改偏好、不重启，也不代替设置页的崩溃报告导出。
