# 试验包 alpha2

通知上划清除后短暂空档的保守修复：更新 IdleIsland 为 `1.1.9.2~alpha2`。AdaptiveColor 无需更换。

- [IdleIsland 1.1.9.2~alpha2](./MangoIdleIsland-1.1.9.2~alpha2-RootHide-arm64e-experimental.deb?raw=true)
- [IdleIsland 1.1.9 原版回退](./MangoIdleIsland-1.1.9-original.deb?raw=true)
- [AdaptiveColor 0.1.3.3~alpha1，上一轮候选，未改](./AdaptiveColor-0.1.3.3~alpha1-RootHide-arm64e-experimental.deb?raw=true)

均为 iOS 16.5 / RootHide / arm64e。安装 IdleIsland 后重新启动用户空间，再检查通知上划清除、长按回弹和音乐切换。如有异常，允许降级安装原版 IdleIsland，并重新启动用户空间。

[9组检查、三版本实际helper运行及完整构建的成功CI](https://github.com/Zeimochenxun/MangoUpsideDownProbe/actions/runs/36719975017)

构建源码 commit：`2d4f6bf7909edb0c5f2b2991ef2c12696ef425a5`。本版修复已在代码中复现的 0.5 点门限空档，尚未取得本次退出的设备日志，真机问题是否消除仍需安装观察。

| 文件 | SHA256 |
|---|---|
| IdleIsland alpha2 | `2af16c9f1cf7266c839ee62d9979ae3d3b7715e37507f762226cda7517928669` |
| IdleIsland 原版1.1.9 | `e6bd2aec00ac552d9c11f37eb287b622413b3e4221e0f2f6f091862493c85b88` |
| AdaptiveColor alpha1 | `161e3a7376bc705708de7a79905028643b458475341365bc1857b6fe16afcaee` |
