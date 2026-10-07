# Beta9 运行时诊断

完整包 `MangoSuite-1.2.0-Beta9.1-RootHide-arm64e.deb`，版本 `1.2.0~beta9.1`。日常安装不需要运行 collector；出现异常时可选使用。

每个模块的诊断会话最多 1200 秒（20 分钟），日志约 256 KiB。只记录现有方向决策、视图几何、透明度和裁剪，不读取媒体标题、封面或授权。采集不会改变偏好、方向、进程或模块时限，只立即复制限定日志末尾（每个候选文件最多 1 MiB）并退出。

1. 安装完整包，在多巴胺中重新启动用户空间。
2. 在重启后 20 分钟内复现异常，记录具体时刻、操作顺序、桌面/锁屏/启动器方向及灵动岛上下滑结果。
3. 使用通常的 mobile 用户，在终端执行：

```sh
sh /Library/MangoSuite/Diagnostics/capture-runtime.sh
```

终端立即打印 `/var/mobile/Documents/MangoSuiteDiagnostics/runtime-日期-时间-随机值.tar.gz` 的绝对路径。用同一终端的路径或 Filza 取回文件。若打包失败则保留快照目录；日志不存在、无权限或读取失败均记入 metadata.txt，不需要 sudo。

快照中的 diagnostic-idle、diagnostic-world、diagnostic-split 候选分别来自当前诊断目录。shell 和 rootfs 独立保留来源路径、时间及文件状态，不能仅凭文件存在认定来自本次进程。legacy 候选只作旧路径补充历史，不能当作新版本实时证据。

没有触发异常时记录“未触发”；无需反复重启或更改开关。日志里的 activity 或 transform 不能证明标题、封面像素可见，也不能证明实际触摸效果。
