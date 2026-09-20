# HoverTranslate 版本记录

## 2026-09-20 网页命中可靠性与跨行整句（**未发版**，落在 0.7 的未提交工作区里）

依据 `docs/superpowers/specs/2026-09-19-web-hit-and-cross-line-sentence-design.md`。两件事：**网页短控件不再"时好时坏"**，
**整句不再被排版换行截断**。翻译引擎、收藏、词库、来源/排除策略、剪贴板规则都没有改动。

### 变更
- **短控件标签**：角色新增 `AXDisclosureTriangle`（Chrome 把 Google Workspace 顶部导航项暴露成它，而不是按钮，
  所以同一控件上"落在文字上能翻、落在内边距上翻不了"）；标签候选增加 `AXDescription`；自身没有标签时，
  只向下看**一层**、最多 8 个直接子节点，要求同一个 PID、矩形与控件相交、是文字角色，并且**只有一个**非空候选
  （两个以上就放弃，不拼接）。结果仍然是 `label` 范围，绝不冒充单词。
- 短控件新增前置条件：控件矩形有效，并且**指针在矩形内**（此前完全不看矩形）。这是设计 §3.2 的要求，
  也意味着"短控件不报矩形"的应用会从"能读标签"变成"读不到"（登记在 ACCEPTANCE J10）。
- **统一跨行句子边界**：新增 `Core/SentenceContextNormalizer.swift`（同一段里的单个换行——含两侧空白、CRLF 记一次——
  压成一个空格，空行原样保留为段落边界；同时保存规范化偏移与原文范围的逐单元双向映射），
  重写 `Core/SentenceResolver.swift`（两阶段：先规范化，再用系统分句器找候选，最后按有效终止符、窗口裁切与段落边界
  判定完整度）。`Dr.`、`3.14`、`example.com` 不误断句；句末标点连同尾随引号/括号属于句子。
  AX 与 OCR **共用同一个解析器**；无法证明左右边界时标 `partial`（沿用卡片上的 "select the full sentence" 提示）。
- **OCR 跨行整句**：先按几何把命中的词所在的那一块行拼成本地文本，再交给同一个解析器；卡片锚点用这句话覆盖的
  词框并集。最多 6 行；双栏、表格单元格、大水平跳跃、异常行距、方向不一致都会断开；上限 2000 UTF-16 单元，
  放不下的行整行丢弃、不切断。只有在截图里能证明左右边界时才标 `complete`，否则仍是 `partial`。
- **识别器不再丢标点**：`.byWords` 会把句号从词里去掉，导致（1）拼出的句子没有终止符、边界永远无法证明，
  （2）送翻译的原文丢标点。现在词后面的标点单独保存（`OCRWord.trailing`）：**词模式返回的仍然只是那个词**，
  句子文本则带着标点。
- 日志新增两类**类别**行（不含正文、URL 或坐标）：`short control role=… origin=…`、`sentence boundary=…`。
- **版本号未变**：仍是 0.7/7。本轮与 v0.7 在同一个未提交工作区里，是否递增版本号等用户授权提交时再定。

### 不做
- 不改翻译供应商/提示词/上限、缓存键、收藏与词库；不改来源策略与排除列表；不改剪贴板规则。
- 不做 OCR"最近单词"搜索、不扩大命中容差、不整页遍历 AX、不持续截图。

### 验证（本次真实执行）
- 红：`-only-testing:HoverTranslateTests/SentenceResolverTests` 退出码 65
  （`'Resolution' is not a member type of enum 'HoverTranslate.SentenceResolver'`），`.build/webhit-red.log`。
- 绿：Debug 全量退出码 0、`TEST SUCCEEDED`、**301 passed / 0 failed / 0 skipped**（xcresult 实读；上一轮 265，本轮 +36），
  `.build/webhit-green2.log`。
- Release 构建退出码 0、本项目源码 0 warning；`codesign --verify --deep --strict` 通过
  （`valid on disk` / `satisfies its Designated Requirement`，designated requirement 不含 cdhash）。
- **未运行**：Release 复制件的启动抽查（本轮不启动第二份实例，避免与用户正在运行的那一份混淆）——标 NOT RUN。
- 真机项（ACCEPTANCE **J01–J10**）全部 **NOT RUN**，只能由用户操作，不预填 PASS。
- **未提交、未推送、未发布**：提交需要用户单独授权。

## v0.7（2026-09-19）单词的词性与多个意思：随包的离线词库

悬停一个单词时，卡片除了译文之外多出一段 `Dictionary · On-device`：**按词性出现顺序**列出该词的意思
（如 `n. 跑, 赛跑` / `vi. 跑` / `vt. 使跑`）。数据是随应用分发的本地文件，**不联网、不需要 Key、不需要任何新权限**，
也不是模型生成的。

### 变更
- `Dictionary/WordBook.swift`（新）：解析随包的两个文本文件并做查询。上限规则写在一个纯函数里：
  **最多 3 条意思**，**同一个词性最多 2 条**；有 3 个及以上词性时每个词性各 1 条（"多种词性则依次列出"），
  两个词性时多出来的一条归前面的词性；还有更多时 `truncated` 为真，卡片显示 `…`。
- `Dictionary/WordSenseProvider.swift`（新）：`WordSenseProviding` 协议 + `BundledWordBookProvider` actor。
  2.6 MB 的文本在 actor 的执行器上解析（**不在主线程**），之后查询是内存字典命中。资源缺失不是错误：返回 nil，卡片就没有词典段。
- `Resources/WordBook.tsv`（2.03 MB，43342 条）与 `Resources/WordBookLemmas.tsv`（0.59 MB，35171 条"变形 → 原型"）：
  由 `tools/build-wordbook.py` 从 ECDICT 的 `ecdict.csv` 生成；来源与许可见 `docs/THIRD_PARTY_NOTICES.md`。
- 查询顺序：精确词 → 去掉所有格 `'s` → 词形映射回原型。变形词自己有词条时用它自己的（例如 `settings`）。
- `Core/TranslationCoordinator.swift`：`show(_:generation:)` 之后按 `scope == .word` 发起词库查询；
  结果只在 `shownSnapshot?.generation` 仍相同（且卡片 `sessionID` 相同）时才下发，所以迟到的词库结果不会写到新卡片上。
  两处取消路径都会取消这个任务。`CardPresenting` 增加 `setDictionary(_:for:)`。
- `Presentation/TranslationCard.swift`：新增词典段（标题 `Dictionary · On-device`，与译文、`AI explanation · not a dictionary entry` 三段互不混淆）。
- `project.pbxproj` 新增 **Resources 构建阶段**（本工程此前没有任何资源文件），并把两个数据文件加入 app target。
- 应用版本 0.6/6 → **0.7/7**。

### 不做
- 只对**单个单词**生效：整句、短语、按钮/菜单标签都不查词库（`scope` 为 `.label`、`.sentence`、`.selection` 一律跳过）。
- 不做语境判断、不出例句、不出音标、不假装知道"当前这句里是哪个意思"。
- 不调用任何在线词典或未授权接口；不读取、不复制 Apple 系统词典的内容。
- 不使用 ECDICT 的 `lemma.en.txt`（其声明仅限研究/教育用途），词形映射改由 csv 自带的 `exchange` 字段生成。

### 验证（本次真实执行）
- 红灯：只有 `WordBookTests` 时 `cannot find type 'WordBook' in scope`，退出码 65（`.build/v0.7-wordbook-red.log`）。
- Debug 全量：退出码 0、`TEST SUCCEEDED`、**265 passed / 0 failed / 0 skipped**（xcresult 实读；上一轮 252，本轮 +13）。
- 其中一条测试直接验证**资源真的进了 app 包**（`testTheBundledWordbookAnswersForTheCommonCase` 从 `Bundle.main` 读 `run`/`settings`/`button`）——
  这条会在"资源没被拷贝"时立刻失败。
- 真机项（ACCEPTANCE **I01–I10**）全部 **NOT RUN**，必须由用户操作，不预填 PASS。
- **未提交、未推送、未发布**：提交需要用户单独授权。

## v0.6（2026-09-18）悬停已选中文本：按住触发键把指针移到选区上

新增一条与快捷键并行的选区入口：**先选中英文，再按住触发键把指针移到选区上停住**，约 250 ms 后浮窗出现并翻译整段——
不需要按快捷键、不写剪贴板、不新增权限。

### 变更
- `HoverTranslate/Core/SelectionHitPolicy.swift`（新）：判定指针是否落在当前选区上。几何必须命中；应用能报出指针处
  字符范围时，序号也必须落在选区内（挡掉多行选区并集矩形造成的误命中）。容差 2pt，只覆盖像素取整。
- `HoverTranslate/Extraction/AccessibilityTextExtractor.swift`：`AXControlReading` 接缝新增 `focusedControl()`、
  `selectedRange(of:)`、`selectedText(of:)`；`read` 在辅助功能权限门之后、命中接口之前插入一次选区探测。
  顺序是"焦点控件 → 来源 PID 核对 → 安全控件 → 选区范围 → 几何 + 序号判定 → 才读正文"；最常见的负例
  （没有选区）只多 2 次 AX 调用，且不读任何正文。任何失败都返回 nil 继续原有单词/整句/标签路径，**不抛错**
  （抛错会被归类为读取失败，可能进入截图兜底）。日志只有类别名与角色名：`selection probe outcome=<…> role=<…>`。
- 正文上限沿用 4000 个 Unicode 字符（超限拒绝、不截断），选区模式请求上限沿用既有的 2400 tokens。
- 应用版本 0.5/5 → **0.6/6**。

### 不做（按计划）
- 不改协调器、请求构造、缓存键、卡片、快捷键入口、设置界面；不为这个手势增加设置开关。
- 不合并"悬停选区"（浮窗卡片）与"快捷键选区"（手动窗口）两个入口。

### 验证（本次真实执行）
- 红灯：只有测试文件时 `cannot find 'SelectionHitPolicy' in scope`，退出码 65（`.build/v0.6-task1-red.log`）。
- Debug 全量：退出码 0、`TEST SUCCEEDED`、**252 passed / 0 failed / 0 skipped**（xcresult 实读）；
  基线 233（本轮开工前把 v0.5 整改轮提交为 `08d94c5`），本轮 +19。
- Release：退出码 0、`BUILD SUCCEEDED`、`codesign --verify --deep --strict` 通过；本项目源码 0 warning；产物 0.6 / 6。
- 真机项（ACCEPTANCE **G01–G11**）全部 **NOT RUN**，必须由用户操作，不预填 PASS。
- **未提交、未推送、未发布**：提交需要用户单独授权。

## 2026-09-18 悬停可靠性修复轮（v0.5 工作区，未提交、未发布）

依据 `docs/HOVER_RELIABILITY_DIAGNOSIS_AND_FIX_PLAN_2026-09-18.md` 的 R1–R4。**没有递增版本号**，没有提交或发布；
按该文档也不替换正在运行的应用。用户反馈"很多页面不灵敏、时常不弹框"，本轮修掉其中**已确认**的机制缺陷。

### R1 AX 命中坐标（已确认缺陷，最高优先级）
- `AXUIElementCopyElementAtPosition` 与 `AXRangeForPosition` 都要求**左上为原点**的屏幕坐标，而指针是 AppKit 坐标。
  此前"找控件"直接用了 AppKit 坐标、"找字符"才转换，两者可相差整屏高度：上下两端会命中别处；同应用内会命中别的控件
  （返回错误标签），跨应用则被 PID 校验拒绝（`unknownOwner`，该类别按策略不允许 OCR 兜底）。
- 现在**只转换一次**，两个调用共用同一个点；返回的文字框仍按原约定转回 AppKit。
- 新增 `AXControlReading` 接缝（真实实现 `SystemAXControls`，保留原 PID / 密码框 / 超时语义），于是整条
  命中 → 单词/整句/标签的判定都能用**假控件**做单元测试：`AccessibilityTextExtractorTests` 12 项，覆盖主屏顶/中/底、
  上方与左侧副屏的负坐标、只转换一次、来源不符/密码框/无权限时正文读取 0 次、映射类别仍决定失败种类。
- 红证据：把转换去掉后这 4 条坐标测试真实失败（`.build/r1-red-proof.log`），恢复后通过。

### R2 OCR 限流：从"终止失败"改为有界等待
- `OCRRateLimiter.earliestStart(now:)`：限流是"何时"而不是"不"。
- 协调器保留**一个**待办（`PendingOCR`），到期那次 tick 重新核对：触发键仍按住、代次有效、模式未变、指针仍在原稳定半径内、
  指针下窗口仍是同一个已确认窗口、排除列表与捕获权限仍允许，然后**补试一次**。
- 不满足即丢弃（不再排第二次）；一次悬停最多一个待办；已有截图未结束时到期也不重叠启动第二个（`ocrInFlight`）。
- 松键、移动、切模式、切应用、锁屏、关开关、改排除列表都会清掉待办。

### R4 失败不再静默
- 读不到文字时在浮窗位置显示一行**原因**（复用 `ExtractionFailure.message`；非激活、点击穿透、约 1.4 s 自动消失、
  同一句 1.5 s 内不重复）；等待截图限流时显示 `recognizing…`，不算失败。
- 状态不是结果卡：没有原文、没有按钮，固定卡片永不被覆盖，松键/换来源后不会迟到重弹（同一代次校验）。

### R3 诊断（未做兼容扩展）
- 只新增不含正文的诊断日志：命中行的 `role` 与位置映射类别、失败原因类别、补试的等待/启动/丢弃。
- **没有**扩展标签角色，也**没有**动 `PointerWindowPicker` 的窗口层级过滤：按诊断文档要求，先采集真实页面证据再决定。

### 验证（本次真实执行）
- 自动测试 **226 passed / 0 failed / 0 skipped**，`TEST SUCCEEDED`（日志 `.build/final-reliability-test.log`；上一轮 205）。
- 真机项全部 NOT RUN：见 `docs/ACCEPTANCE.md` 的 H 组（Chrome 正文顶/中/底、导航栏、多屏、真实补试与状态摆放）。

## 2026-09-18 整改轮（v0.5 工作区，未提交、未发布）

依据外部只读审阅 `docs/PROJECT_REVIEW_2026-09-18.md` 的 R1–R7。**没有递增版本号**（仍 0.5 / build 5），
也**没有提交或发布**；下面每一项都对应当前工作区里实际生效的代码。

### 读取边界
- **R1 选区入口的来源**：`SelectionTextExtractor` 改为读**键盘焦点控件**的 PID 与角色（`SelectionFocus`），
  不再用鼠标下的窗口充当来源。协调器 `handleSelectionRequest` 的顺序是
  "解析焦点 → 用 PID 解析 bundle ID → 排除列表 / 无法归属 / 安全控件检查 → 才读取选区正文 → 上传前再核对请求代次与最新排除规则"。
  被排除、无法归属或受保护的控件：选区正文读取 0 次、网络调用 0 次。读取期间焦点改变
  （`AXUIElementGetPid` 与确认时不一致）返回 nil，不发送。
- **R6 失效流程**：改排除列表（`translationPolicyChanged`）、保存/删除 Key（`translationCredentialsChanged`）、
  关闭云端翻译（`translationDisabled`，设置里的开关）、锁屏与休眠（`sessionWentInactive`，由 `TriggerController` 的
  `screensDidSleep` / `sessionDidResignActive` 触发）都先使旧代次失效并取消在途任务，再清缓存；
  手动"清缓存"同样先失效在途请求，否则清空后旧结果会立刻写回。切应用仍是原来的 `externalChange`（只取消，不清缓存）。

### 交互
- **R2 不再预填剪贴板**：删除 `prefillManualFromClipboard()` 与带布尔参数的 `revealManualWindow`；
  选区读取失败与菜单入口都只打开**空**输入框并提示粘贴（`ManualPresenting.promptForManualPaste`）。
  剪贴板只在用户点 Copy 时被写。
- **R5 手动窗口的 Copy result** 改为调用 `copyManualResult()`（此前错接到悬停卡片的 `copyDisplayedText()`）。
  两个入口的接线集中在 `ManualActionWiring.wire`，测试调用同一个接线函数，而不是只测被调用的方法。
- **整句修饰键（2026-09-18 变更，用户要求）**：悬停整句由"触发键 + Shift"改为"触发键 + **Control**"。
  `TriggerPolicy.mode` 的参数 `shift` 改为 `control`；`TriggerController` 改为跟踪左右 Control（keyCode 59/62，仍走 `.flagsChanged`，
  不读字符、不吞事件）；`TranslationCoordinator.optionStateChanged(control:)` 同步改名；菜单与设置的说明文字改为 Control。
  **Shift 不再切换模式**（按住 Shift 悬停仍是单词/标签）；类型上已无法再传入 shift。
  自动测试 205 passed / 0 failed / 0 skipped（`TEST SUCCEEDED`，用例数与改动前一致，只改断言与命名）。
  未实测：Control+Option 是 VoiceOver 的默认组合键（本机未启用 VoiceOver）。
- **R4 选区快捷键**：`SelectionShortcutController` 改用公开的 `RegisterEventHotKey` + `InstallEventHandler`
  （`CarbonHotKeyRegistrar`），不再用 NSEvent 监视器。注册结果（noErr / eventHotKeyExistsErr / 其它）直接显示在菜单与设置里；
  切换预设先释放旧组合；退出时释放。无法检测"用事件监视器自己监听键盘的应用"这一限制写进了界面与指南。

### 可诊断性
- **R3 阶段耗时日志**：`logTiming` 恢复插值。实测日志已能读到 `stage=accessibility gen=1 ms=0 outcome=success`
  （此前输出的是字面量 `stage=(stage, privacy: .public)`，并伴随"变量未使用"警告）。
- 新增一行注册结果日志：`selection shortcut Control-Command-T status=0`（只有预设标签与状态码，无用户文本）。

### 验证（本次真实执行）
- 自动测试 **205 passed / 0 failed / 0 skipped**（v0.5 为 188），`TEST SUCCEEDED`；
  新增：选区来源 6 项、单次按键 1 项、策略/密钥/锁屏/关闭翻译失效 4 项、手动 Copy 接线 1 项；`SelectionShortcutTests` 重写为注册生命周期（10 项）。
- Release 构建退出码 0、本项目源码 0 warning；`codesign --verify --deep --strict` 通过；designated requirement 不含 cdhash。
- Release 复制件启动实测 10 秒无退出，日志实测 `status=0`（系统接受注册）；两份实例同时注册同一组合都返回 0（系统不把它当冲突）。
- 真实环境的端到端验收（R8）**未执行**：见 `docs/ACCEPTANCE.md` 的 F 组，全部 NOT RUN。

### 文档（R7）
`README.md` 顶部改为当前状态并给出构建命令；设计文档 §3.3/§4/§8/§10 按实现改写并注明日期；
`docs/PROJECT_STATUS.md` 顶部建立唯一的"当前状态"；`docs/ACCEPTANCE.md` 新增 F 组并修正 B07/B10 的旧引用；
本文件新增本节。

## v0.5（2026-09-18）全局可用：排除列表取代允许列表

### 变更（用户明确要求）
用户要求"任何应用都能取词，不再逐个添加允许列表"。因此来源策略由**允许列表**反转为**排除列表**：

- `SourcePolicy` 默认允许一切；设置里的列表变成"不要读取这些应用"。
- 设置界面：`Applications` 区块，空列表显示 "No applications excluded"，按钮改为
  `Exclude Application…` / `Include Again`；OCR 说明文字同步改为"you have not excluded"。
- 排除的应用在**任何读取之前**就被拒绝：不会进入 AX 取词，也不会进入 OCR 兜底。
- 仍然拒绝的两类：**没有 bundle ID、无法归属的来源**（原来是"不在允许列表"，现在是"无法归属"，
  失败原因记为 `unknownOwner`），以及密码框/安全控件（`blockedSensitive`）。这两条没有放松。
- 提示文案：`appNotAllowed` 现在是 "this application is excluded in Settings"。

### 升级安全（最重要的一点）
旧的允许列表存在 `HoverTranslate.allowedBundleIDs`，含义是"只有这些应用可读"。**没有迁移、也不会被读取**：
把它解释成排除列表会静默屏蔽你当初主动勾选的应用（例如 TextEdit、Codex）。新设置存在独立的键
`HoverTranslate.excludedBundleIDs`，旧键留在那里不再使用。
测试 `SettingsStoreTests.testTheOldAllowListIsNeverReadAsAnExclusionList` 固定住了这条。

### 文档同步
`AGENTS.md` 与设计文档 §4 里"允许列表默认空"的规则已按本次授权改写（注明日期与原因）；
`docs/USER_GUIDE.md` §3/§8 同步。这是行为约定的变更，不是实现偏差。

### 自动测试
**188 passed / 0 failed / 0 skipped**（v0.4 为 182）。新增 `SettingsStoreTests`(5)，
`SourcePolicyTests` 改为排除语义（3 项），`TranslationCoordinatorTests` 新增
"没有排除列表时任意应用都可读""没有 bundle ID 的来源仍被拒绝"，`TranslationCacheTests` 改为排除语义。

### 版本
`MARKETING_VERSION = 0.5`、`CURRENT_PROJECT_VERSION = 5`。

## v0.4（2026-09-17）学习与本机交付

### 新增
- **主动收藏（Save）**：松键后的卡片上点 `Save` 才保存（原文 + 译文 + 已经发送过的短语境）。
  存放在 `~/Library/Application Support/HoverTranslate/SavedEntries.json`，使用原子写入。
  普通悬停、缓存命中、Pin、解释都不会自动保存任何东西。
- **收藏管理**：菜单栏 `Saved Entries…` 与设置里的 Saved entries 区块，支持单条删除与全部删除。
  文件损坏时明确提示、**保持文件原样**，只有用户点 `Delete All…` 才会重写。
- **按需解释（Explain）**：按钮只出现在已冻结/固定的可交互卡片上，点击后才发请求。
  使用独立的解释提示词（只讲当前语境含义、必要时一句用法说明），输出上限 900 tokens，卡片上标明
  `AI explanation · not a dictionary entry`；不生成词源、音标或例句列表。
- **设置收尾**：`Clear cached translations`（真实清空并报告条数）、选区快捷键可选择（默认 Control-Command-T）、
  Saved entries 区块（条数 / 打开 / 全部删除）。
- 版本号：`MARKETING_VERSION = 0.4`、`CURRENT_PROJECT_VERSION = 4`。

### 修复（本次实测发现，不是推测）
- **模型设置此前不起作用**：`DeepSeekTranslationService` 无论设置里选哪个模型，请求体里始终写死 `deepseek-flash`，
  于是"模型"只影响缓存键、不影响真实请求。现在模型由配置层作为参数传入，请求体实测带上所选模型；
  空模型在发起请求之前就拒绝。新增两个测试覆盖。
- **收藏文件日期精度**：ISO-8601 编码丢掉亚秒，导致一条收藏写盘再读回来与原对象不相等（身份变化）。
  改为 Foundation 默认的全精度日期编码，并新增"重启后条目身份不变"的测试。
- 菜单项 `Translate Selected or Pasted Text…` 不再绑定写死的 Control-Command-T：真实快捷键是可配置的全局监视器，
  写死的菜单快捷键既会误导，也可能让同一个请求触发两次。

### 构建与环境
```bash
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Release -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates build
```
- 实测产物：`$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`
  （CFBundleShortVersionString 0.4 / CFBundleVersion 4 / 3.4 MB），`codesign --verify --deep --strict` 通过，
  designated requirement 不含 cdhash。
- **与计划文档的一处偏差**：计划里的 `-derivedDataPath .build/DerivedData`（项目目录内）在本机不可用——
  iCloud/FileProvider 会在签名之后写回 `com.apple.FinderInfo`，`codesign --verify` 实测报
  `resource fork, Finder information, or similar detritus not allowed`。DerivedData 必须放在项目目录之外。
- 启动实测：Release 构建复制到 `/tmp` 后启动，12 秒无退出、无输出、`DiagnosticReports` 无新崩溃报告，随后主动结束；
  没有干扰正在运行的实例。

### 自动测试
**182 passed / 0 failed / 0 skipped**（v0.3 为 155）。新增 `LearningStoreTests`(7)、`ExplanationRequestBuilderTests`(4)、
`SelectionShortcutTests`(5)，并扩充 `TranslationCoordinatorTests`(+8)、`TranslationServiceTests`(+2)。

### 未实测（需要用户手动）
真实整句取词、真实屏幕录制授权后的截图 OCR、多屏摆放、真实 DeepSeek API 翻译、剪贴板不变、
深浅色与较大字号排版、Saved entries 窗口的键盘操作。逐项状态见 `docs/ACCEPTANCE.md` 的 A/B/C/D 组。

## v0.3 / v0.2 / v0.1
见 `docs/PROJECT_STATUS.md` 中对应的会话记录（v0.3：悬停整句与 OCR 兜底；v0.2：DeepSeek 翻译、选区与缓存；
v0.1：触发键与 AX 取词）。
