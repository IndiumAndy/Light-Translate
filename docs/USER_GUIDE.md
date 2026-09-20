# Light Translate 使用指南（v0.5，含 2026-09-18 整改轮；本机自用）

本指南只描述**已经实测**或**已被可重复自动测试覆盖**的行为；未验证的项目在第 6 节与第 8 节单列，不要当成已验证。
Light Translate 是菜单栏工具（`LSUIElement`），不显示 Dock 图标，不修改系统安全策略，也不安装后台服务。
2026-09-18 的整改改动（选区来源、剪贴板、快捷键注册、缓存失效）**尚未提交、尚未发布**；本节描述的就是当前工作区的行为。

## 1. 打开应用

构建产物在同一 DerivedData 下有两份，bundle ID 都是 `com.atat.HoverTranslate`，**同时只运行一份**：

| 用途 | 实际路径（本机实测存在） |
|---|---|
| 日常使用 | `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app` |
| 调试 | `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Debug/HoverTranslate.app` |

```bash
open "$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app"
pgrep -fl HoverTranslate    # 期望只有一行
```

> **不要**把 DerivedData 放进项目目录。计划文档里的 `-derivedDataPath .build/DerivedData` 在本机实测会产生一个
> 签名无效的 .app：该目录由 iCloud/FileProvider 管理，签名完成后系统又写回 `com.apple.FinderInfo`，
> `codesign --verify` 报 `resource fork, Finder information, or similar detritus not allowed`。
> Debug 与 Release 都必须用项目目录之外的路径。

如果菜单栏出现两个图标，说明有两份实例在跑：辅助功能授权只会落在其中一份上，另一份会一直显示授权按钮。
（2026-09-18 实测：两份实例各自注册同一个选区快捷键都会成功，系统不把它们当作冲突。）

## 2. 首次使用：两个都可以拒绝的权限

1. **辅助功能（必需，没有它看不到触发键，也读不到选区）**：菜单栏图标 → `Grant Accessibility Access…`，
   或 系统设置 → 隐私与安全性 → 辅助功能。
2. **屏幕录制（只有你要用 OCR 兜底时才需要）**：设置 → Screenshot fallback → 打开开关 → `Request…`。
   - 不授权也能用：单词、整句、选区、翻译都不需要它。
   - 拒绝之后应用不会反复弹窗、不会绕过；只是 OCR 不工作。
   - 授权后系统可能要求重启应用。

选区快捷键的**注册**不需要辅助功能权限，但**读取选区正文**需要；没有授权时按快捷键只会提示手动粘贴。
应用**不会**替你读取任何已有的 Key，也不会替你授权。

## 3. 怎么用

| 想要 | 操作 |
|---|---|
| 单词/标签 | 按住触发键（默认右 Option，可在设置里切成左 Option），把鼠标停在英文上 250 ms；单词会多出一段词性与释义（见下） |
| 整句 | 同上，同时按住 Control（中途按下或松开 Control 会作废当前请求并重新计时）。**排版换行不再截断句子**：同一段里折行的整句会一起读出，空行（段落边界）仍然断开 |
| 选区翻译 | 在任意应用里选中英文，按设置里的 Selection shortcut（默认 Control-Command-T） |
| 整段选区（不用快捷键） | 先选中英文，再按住触发键把鼠标移到选区上停住 250 ms → 直接出现浮窗并翻译整段 |
| 手动粘贴 | 菜单栏 → `Translate Selected or Pasted Text…` |
| 收藏 | 松键后卡片上出现按钮 → `Save` |
| 解释 | 松键后 → `Explain`（只解释当前语境；卡片上标明是 AI 解释，不是词典条目） |
| 固定 | `Pin`；固定卡片不会被新的悬停覆盖 |
| 查看/删除收藏 | 菜单栏 → `Saved Entries…`，或设置里的 Saved entries |

**读不到时不会静默**：浮窗位置会短暂出现一行原因（例如 `no exact text at this position`、`this application is excluded in Settings`），
约 1.4 秒后自行消失，不抢键盘焦点、不遮挡鼠标位置；同一句话在 1.5 秒内不会重复出现。
开了 OCR 兜底时，截图限流（相邻两次至少 800 ms）期间的等待显示 `recognizing…`，等到间隔满足后**自动补试一次**；
若这期间你松了触发键、移动了指针、换了应用或把该应用加入排除列表，这次补试会被丢弃，不会去截旧窗口。

**所有应用默认都能取词**，不需要逐个添加。设置里的 `Applications` 区块是一个**排除列表**，默认空；
只想让某个应用不被读取时，用 `Exclude Application…` 把它加进去。密码框和其它受保护控件在任何应用里都不会被读取。
（旧版本存下的"允许列表"不会再被读取，也不会被当作排除列表使用——否则你当初勾选的应用反而会被屏蔽。）

**选区入口的来源是键盘焦点控件所属的应用**，不是鼠标位置：先确认来源（是否被排除、能否归属、是否安全控件），
确认通过才读取选区正文，读取完成后、发送前会再核对一次最新规则。被排除的应用、无法归属的来源和密码框都读不到任何内容。
**读不到时只会打开一个空输入框**，应用不会替你读剪贴板；你粘贴什么、是否按 Translate，都由你自己决定。
手动窗口的 `Copy result` 复制的是这个窗口里的译文（没有译文时不复制），与悬停卡片互不影响。

## 4. 需要你自己输入的东西

- DeepSeek API Key：设置 → `DeepSeek API key` → `Save key`。
  Key 只写进本应用自己的 Keychain 项（service `com.atat.HoverTranslate`），**不写** UserDefaults、源码或日志。
  保存或删除 Key 都会让在途请求失效并清空内存缓存，旧 Key 下拿到的结果不会继续显示。
- `Test Connection` 只发送合成文本 `Open Settings`，不会发送你屏幕上的任何内容。

## 5. 延迟与费用不是固定值

- 250 ms 是稳定的**触发**等待，不是翻译延迟。整条链路（悬停判定 → AX 读取 → 缓存 → 网络）的实际耗时依网络与模型变化。
- 本版本按阶段记录耗时（`stage=accessibility|ocr|cache|translation gen=<n> ms=<n> outcome=<类别>`，只有数字与类别名）。
  2026-09-18 整改修好了这行日志此前输出成字面量（`stage=(stage, privacy: .public)`）的缺陷，现在实测能读到
  `stage=accessibility gen=1 ms=0 outcome=success` 这类真实记录；但**仍未采集真实样本**，所以这里不提供任何秒开或 p95 结论。
- 费用按官方定价与你的实际用量计算。应用不批量请求，也不自动重试付费请求。
- 自动查询不会触碰剪贴板；只有你点 `Copy` / `Copy result` 才会写剪贴板。

## 6. 已实测 / 未实测

**已实测**
- 构建、签名、启动：Release 与 Debug 都能启动并稳定运行；designated requirement 不含 cdhash，
  **重新构建不需要重新授予辅助功能权限**。
- 自动测试 **226 项通过 / 0 失败 / 0 跳过**（2026-09-18 悬停可靠性修复后实测，证据见 `docs/ACCEPTANCE.md` 的 H 组与 F 组）。
- 本轮修掉一个真实缺陷：命中控件时漏做 AppKit → AX 坐标转换，屏幕顶部/底部区域会命中别处（甚至命中别的应用的控件而被拒绝）。
  它有"红证据"：把转换去掉后新测试真实失败，恢复后通过。
- Release 复制件启动实测：运行 10 秒无退出，日志实测 `selection shortcut Control-Command-T status=0`
  （系统接受了快捷键注册），随后主动结束，未干扰你正在运行的实例。
- 真机：悬停取词确实出现过（v0.1 验收）；松键后 Pin/Close 按钮可点击；快速换词能正确切换。

**未实测（不要当成已验证）**
- 快捷键**冲突**的真实提示（本机没有第二个应用占用这组预设；两份本应用实例各自注册都会成功）；
- 真实整句取词范围；真实屏幕录制授权后的截图 OCR；多屏摆放；真实 DeepSeek API 翻译；
  选区入口在真实应用上的端到端表现；深浅色与较大字号下的排版；Saved entries 窗口的键盘操作。

## 7. 撤销与清理

| 想撤销 | 怎么做 |
|---|---|
| 辅助功能授权 | 系统设置 → 隐私与安全性 → 辅助功能 → 关掉 HoverTranslate |
| 屏幕录制授权 | 系统设置 → 隐私与安全性 → 屏幕录制 → 关掉 HoverTranslate |
| API Key | 设置 → `Remove key`（同时让在途请求失效并清空内存缓存） |
| 缓存 | 设置 → `Clear cached translations`；缓存只在内存，退出应用即消失 |
| 收藏 | `Saved Entries…` → 单条 `Delete`，或 `Delete All…` |
| 彻底移除 | 菜单栏 → `Quit HoverTranslate`；删除 .app；再删除 `~/Library/Application Support/HoverTranslate/` |

收藏文件是 `~/Library/Application Support/HoverTranslate/SavedEntries.json`（原子写入）。
它损坏时应用会**明确报错并保持文件原样**，不会静默清空；`Delete All…` 是你显式同意的恢复方式。

## 8. 已知限制

- 取词依赖目标软件的辅助功能支持。控件不支持位置映射时明确失败，不会用最近的词糊弄。
- 浏览器顶部导航栏、标签栏、书签栏与系统菜单栏属于**不同 AX 层级**，能否取到要按页面实测。
  诊断日志只有类别，不含任何正文：`hit role=… mapping=…`、`short control role=… origin=…`、
  `sentence boundary=…`、`extraction failed reason=…`。
- **2026-09-20 起**：短控件（按钮、菜单项、Chrome 的 `AXDisclosureTriangle` 等）可以从自身的
  `title`/`value`/`description`，或**唯一一个直接文字子节点**得到整个标签（标 `label`），
  所以指针落在控件内边距上也能得到与落在文字笔画上相同的标签；候选不唯一、超长、多行、不相交或不是文字节点时仍然失败，
  不会拼接猜测。另外，短控件现在必须**报出矩形并且指针确实在矩形内**：不报矩形的应用会从"能读标签"变成"读不到"。
  **以上均未在真实网页上验收**（见 `docs/ACCEPTANCE.md` J 组）。
- 只有精确取到单词才标 `word`；短按钮/菜单项标 `label`。
- 句子边界无法确认时标 `partial`，请改用选区翻译；应用不会让模型补写原文。
  **2026-09-20 起**：同一段里的单个排版换行不再截断句子（`This sentence wraps⏎onto another line.` 会作为一整句读出），
  空行/段落边界仍然断开；缩写（`Dr.`）、小数（`3.14`）、域名（`example.com`）不误判为句末。
  读取窗口两端被裁、句末没有终止符、或来源只能给出一行时仍是 `partial`。OCR 多行合并同理：
  只有在截图里能证明左右边界时才标 `complete`，双栏/表格/大间距不会拼成一句。
- OCR 只截取指针下**已确认的那一个窗口**的一小块区域（一次一帧、间隔至少 800 ms），只驻留内存，不写文件、不上传。
- 选区快捷键是固定的一组预设（默认 Control-Command-T），通过系统的公开热键接口注册：
  注册成功、被其它应用占用、注册失败三种结果会直接显示在菜单栏与设置里。
  **无法检测**的是"用事件监视器自己监听键盘"的应用——这类冲突不会被告知，请挑一个你其它软件没在用的组合。
- 选区入口只认键盘焦点控件；焦点在别的应用时，读到的是那个应用的选区（这是正确的来源），而不是鼠标下的窗口。
- 锁屏、屏幕休眠或会话失活会取消在途请求并清空内存缓存；固定卡片保留已显示的内容，但不会保留活动请求。
- 默认对所有应用可读；能限制的只有"逐个排除"。
- 整句模式用"触发键 + Control"。**Control+Option 也是 VoiceOver 的默认组合键**：启用 VoiceOver 时这个组合可能先被系统占用；
  本机未启用 VoiceOver，这一条**未实测**。
- 悬停选区这条手势要求目标应用提供 `AXSelectedTextRange` 与 `AXBoundsForRange`；不提供的应用里这个手势不生效
  （回落到原来的单词/整句悬停），此时仍可用上面的选区快捷键。
- 选区内悬停永远翻译**整个选区**（在选区内按住 Control 也一样）。只想要其中一个单词时，先点一下取消选区再悬停。
- 部分应用不提供 `AXRangeForPosition`，此时只用几何矩形判定，多行选区的边缘可能偏宽——这是如实登记的限制，不是猜的。
- 选区超过 4000 个 Unicode 字符时不发送、不截断，回落为指针处的单词。
- **词性与多个意思**来自随应用分发的离线词库（约 4.3 万条常用词；来源与许可见 `docs/THIRD_PARTY_NOTICES.md`），
  不是在线词典，也不是模型写的。卡片上单独标 `Dictionary · On-device`，与译文来源分开，不冒充 AI 解释。
- 词库**只对单个单词**生效：句子、短语、按钮/菜单标签都不查词库。词库里没有的词（生僻词、专有名词、某些变形）不显示这一段，卡片只显示译文。
- 释义的排列规则是固定的：按词性出现顺序分组，最多 3 条意思，同一个词性最多 2 条；如果还有更多，末尾显示 `…`。
  词库给的是这个词**常见的意思**，它不判断"当前这句话里是哪一个意思"——语境判断仍由你本人或 `Explain`（AI 解释）完成。
- 词库没有例句、没有音标、没有词形变化表。它不联网，所以断网时这一段的显示不受影响。
- 不做账号、云同步、自动更新、开机启动常驻服务或付费功能。
