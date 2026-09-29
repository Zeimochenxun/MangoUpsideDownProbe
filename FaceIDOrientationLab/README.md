# FaceID Orientation Lab 0.1.5-alpha6

第六个原生可安装诊断版，可替换之前版本。新增认证进程中已加载的 BiometricKit 与 libBKDM2 类、方法签名、实现镜像及偏移索引，供定位后续认证判断。只适用于 iPhone 13 mini / iPhone14,4、iOS 16.5 build 20F66、Dopamine RootHide。

**这是定位用插件，安装后不会使倒置 Face ID 自动恢复。没有启用 iPad 伪装、方向改写或认证结果修改。**

## 安装与测试

1. 保存并安装 `com.chenxun.faceidorientationlab_0.1.5~alpha6_iphoneos-arm64e.deb`。包管理器可按 Conflicts 提示移除旧 `FaceIDOrientationProbe`；两者不能同时挂接同一组接口。保留当前 Mango / UpsideDowned 及视觉补丁，测试期间不要更新它们。
2. 在 Dopamine 中执行“重启用户空间”，然后先用密码解锁一次。单纯 Respring 不保证 biometrickitd 加载。
3. 等约 15 秒。认证进程目录还会出现 `BKDM-code-from-4000.bin`；这份文件只保存经镜像 UUID 校验的已加载可执行代码片段（基址偏移 `0x4000`，最多 48 KiB）。本版还生成 `Runtime-method-index.txt`，其中列出两个目标镜像已加载的类、实例变量及方法；其生成情况记录在 `Probe.log` 的 `[INDEX-DUMP]` 或 `[INDEX-SKIP]`。从 Filza 导出索引和同目录的 Probe.log 即可，无需重复刷脸。其他三份代码片段仍会导出。Filza 中会自动出现以下两个目录，各自有 `Probe.log`、`Phase.txt`、`Disable.txt`，不需手动创建。

```text
/var/mobile/Library/Logs/FaceIDOrientationLab-SB/
/var/mobile/Library/Logs/FaceIDOrientationLab-Bio/
```

4. 在启动后的 10 分钟内，按“正常竖屏 → 刘海在左 → 倒置 → 刘海在右 → 正常竖屏”测试。每个方向先停稳约 5 秒，再锁屏、唤醒、尝试一次正常解锁；每轮间隔约 10 秒。失败后用密码恢复，避免反复刷脸触发系统限制。
5. 分别记下五次结果（成功/失败/系统要求密码），以及是否界面自动回正。把两个目录的 `Probe.log` 一起导出，命名为 `SB-Probe.log` 和 `Bio-Probe.log` 以免覆盖。若测试中重启过，也保留 `Previous.log`。

无需编辑 Phase.txt 即可做首轮：SpringBoard 每秒采样公开的 UIDevice.orientation，用日志时间辅助对应。它不是认证输入或独立的可信传感器测量，值也可能被其他插件影响。人工 Phase.txt 只是可选备注，不自动转发到另一个进程。

如果没有目录或仅出现 SKIP，不要自行把目录权限改成777。记录现象即可；没有 HOOK/调用记录并不证明系统没有对应能力。

## 记录内容

- SpringBoard：`UIDevice.userInterfaceIdiom` 与 `SBTraitsSceneParticipantDelegate._orientationMode` 的原始返回值及直接 caller；不替换返回值。保留已经存在的 hook 链，记录当前 IMP 镜像。
- biometrickitd：沿用之前四个严格校验签名和镜像 UUID 的方向观察入口。
- 运行时索引在安装方法钩子之前生成，限制在目标镜像内，大小最多约 1.5 MiB；列出方法元数据，不读取面容数据或认证对象。方法名称本身不证明其负责方向限制。
- biometrickitd：若进程已经加载 `libMobileGestalt.dylib` 且导出 `MGCopyAnswer` / `MGGetBoolAnswer`，额外观察八个列明的设备类型和能力键查询；记录查询键及直接调用者，不读取查询答案，也不改变返回值。`MG-HOOK` 表示挂接成功，`MG-QUERY` 表示测试期间实际查询。没有查询记录可能是启动前已经缓存，不能据此排除该能力判断。
- UpsideDowned 只在 `_orientationMode` 运行期间临时返回 iPad idiom。0.1.0 记录到的 `UIDevice.userInterfaceIdiom=0` 都来自其调用原方法的内层；本版仍不会把该内层值误称为交给系统的最终值。日志无法证明 Face ID 使用这一 UI idiom。
- `[CALLER]`：镜像、UUID、相对返回地址偏移。不是文件偏移，不是已确认的认证 gate。只记录直接调用者，不采集完整调用栈。
- 不记录人脸图像、面容模板、身份对象、密码或认证令牌；统计接口不作为匹配成功证据。

## 停止与恢复

每个进程每次启动最多记录 10 分钟；每方法每秒最多4条、共享队列最多64条，日志最多2MiB并保留一份 Previous.log。达到上限或写入失败会停止记录。到期后计时器和方向通知订阅会清理，已安装的 hook 继续原样转发，直到进程重启；不是动态卸载。

手动停止：将两个目录各自的 Disable.txt 改为 `1`，保留原文件所有者和权限。重新启用需改回 `0`，再重启用户空间。彻底移除需卸载本包并重启用户空间。

安装前确保知道设备密码，能在 Dopamine 关闭插件注入。若出现循环崩溃，强制重启，密码解锁后在关闭插件注入状态下恢复并卸载本包。SpringBoard 安全模式不保证阻止认证守护进程注入。

## 开发与验证

RootHide Theos + Apple Clang + iPhoneOS16.5.sdk，`ARCHS=arm64e`，`THEOS_PACKAGE_SCHEME=roothide`。

```sh
python3 tools/test_recorder.py
make package FINALPACKAGE=1
python3 tools/check_package.py packages/*.deb
```

测试从实际源码提取 C 记录器和六个转发函数，验证恰好调用一次原函数、参数/返回值保留（含UINT64_MAX、INT64_MIN/MAX）、禁用、限流、队列上限、锁竞争、caller捕获、超时和数组边界。

构建检查验证真实 arm64e Mach-O、代码签名命令、RootHide依赖路径、精确注入过滤和无安装脚本。编译/包检查不代表真机加载或 Face ID 行为已验证。
