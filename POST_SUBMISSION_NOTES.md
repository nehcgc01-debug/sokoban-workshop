# 截止后迭代记录（2026-11-18）

## 来源与边界

本地分支基于仓库 main 的 251f85a606a2504630b9a1fcfc920f9ec79075cb，叠加已存在的 StageB_BlindPrep / HostReady v2。v2 运行 ZIP 的 SHA-256：75f1710763f81d9bd0f364ad2c6696d4ce557a4cd0ade28811b770477fad0f09。

main、远端和原提交原件均不改动。本分支明确属于截止后，不倒签、不代交卷。main 与 v2 的差异包含此前菜单、音乐、焦点、退出等迭代，不应误称全部由本轮引导修复新增。具体而言，main 的 config/name 是 Kuro_sukobann_lab6，v2 已是 Kuro_sukobann_menuwarm 并新增 MusicService 自动加载；本轮沿用 v2 的 project.godot 原字节，没有再改存档名或兼容 key。

## 最小游戏改动

只修改 game.gd 的终局汇总文案分支：读取 Catalog.LAB_ORDER 对应已有通关记录；有待完成委托时显示剩余数量及 Enter / N 回菜单邀请，否则显示 E 创作及回菜单重玩。加班单不参与计数。编辑器按键和按钮保留，主线未齐或保存失败时沿用原有汇总显示条件。

新增 tests/post_submission_ending_tests.gd，覆盖待完成委托、委托完成但加班未完成、全部内容完成，以及撤销、保存失败警告、返回菜单焦点、选关推荐与自由选择。原有测试断言未删除或放宽；tests/run_tests.py 仅增加隔离预期路径与新套件入口（本轮未在 Linux 重跑）。

## Windows 验证

- 修改前原生窗口：第11关通关汇总要求按E创作；返回菜单却显示2张委托并聚焦开始游戏，复现引导不一致。
- 修改后剩余委托（960×600）：汇总提示2张委托及 Enter / N；返回菜单开始游戏，进入选关聚焦委托2。
- 修改后委托完成（1152×720，加班未完成）：汇总邀请创作/重玩；返回菜单初始聚焦编辑器。实际 Enter 进入编辑器、Esc 返回；鼠标仍可开始自由选关，推荐第1关重玩，加班未被强制。
- 上述进度由隔离脚本构造，并自动走到最后一步，实际按 Left 推完，不是陌生玩家从头通关。实际窗口三次正常退出码0；另普通桌面双击启动器新会话菜单往返退出0。
- 相关自动套件：post_submission_ending 33/33、workshop_ending 10/10、blind_prep 36/36、interaction_b 69/69、menuwarm_v32 59/59、progress_order 12/12、exit_guard_menu 9/9。共228项。
- post_submission_ending 与既有 workshop_ending 各有退出 ObjectDB 警告；首次冷导入有7条字体/主题ERROR，不作无害承诺。

运行日志、截图、构造存档和主分支旧材料只在仓库外本地保留，不作为公开文件。当前文件树停止收录旧日志/旧验收设计材料，原字节保存在本地归档，main历史仍可追溯。本分支以源码与必要资源为主，不包含引擎和发行包。
