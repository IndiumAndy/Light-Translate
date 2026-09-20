# HoverTranslate 验收矩阵

初始状态：以下项目均未执行。只有实际操作/测试过才能标PASS；同时记录证据来源。
可用状态：NOT RUN、PASS、FAIL、BLOCKED、NOT APPLICABLE。单测PASS不能代替GUI实测PASS。

2026-09-17 更新：v0.1 已实现并构建通过，自动测试 49/49 通过（证据见 `docs/PROJECT_STATUS.md`）。
A 组中带 "自动化" 字样的行由可重复的单元测试覆盖；其余全部需要用户在真机手动操作，**当前仍为 NOT RUN**。

2026-09-17 修复会话更新：自动测试 54/54 通过。修复了"取词来源取的是前台 app 而不是鼠标下的 app"（真机表现为每次悬停都失败并提示 `the pointed window belongs to another application`）以及允许列表拒绝被误报为"需要辅助功能权限"。A02 由用户真机悬停确认**浮窗出现**，但**未**按原定义验证 `word`/`label` 范围区分，也**未**在系统设置里用右 Option 复现；其余行仍为 NOT RUN。详情见 `docs/PROJECT_STATUS.md` 的"修复会话"。

2026-09-17 v0.4 实施完成更新：自动测试 **182/182** 通过，Release 0.4 构建/签名/启动已实测。
D 组带"自动化"字样的行由可重复的单元测试覆盖；真机 UI 操作仍未执行（详见 D 组与 `docs/USER_GUIDE.md`）。

2026-09-17 v0.3 实施完成更新：自动测试 **155/155** 通过。C 组中带"自动化"字样的行由可重复的单元测试覆盖
（包括用程序生成的合成英文图片跑真实 Vision）；**真实整句取词、屏幕录制授权后的真实截图、多屏摆放仍未执行**。

2026-09-18 整改轮更新：自动测试 **205/205 PASS**，Release 构建/签名/复制件启动已实测（证据见 F 组）。新增 **F 组**（整改项）；B07/B10 的旧引用已按新代码更新；真实环境项（R8）全部保持 NOT RUN。

## A. v0.1

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| A01 | 未按触发键，静置1分钟 | AX文字查询、截图、网络计数都不增长 | NOT RUN（结构性保证：无触发不进入取词路径；需要用户按 A 组实测确认） |
| A02 | 右Option悬停Settings | 稳定后显示Settings；单词与label范围如实区分 | 部分 PASS（2026-09-17：修复来源缺陷后用户真机悬停确认浮窗出现；**未**在系统设置里用右 Option 验证，也**未**核对 word/label 区分；用户实际触发键为 Left Option、允许列表为 TextEdit+Codex） |
| A03 | 左Option，或左右同按后只松右Option | 右Option模式不误触发/不粘滞 | 自动化部分 PASS（`TriggerPolicyTests` 5 项：左右按位独立、松开一侧即停、禁用不触发）；实机按键判定 NOT RUN |
| A04 | 鼠标在单词间空白 | 不挑最近的词 | 自动化部分 PASS（`TextResolverTests.testWhitespaceIsNotNearestWord` 等）；实机悬停 NOT RUN |
| A05 | 含emoji的文本、比例字体 | 不因索引或字符宽度取错词 | 自动化部分 PASS（UTF-16 偏移、emoji 前后缀、词内撇号/连字符、变音符）；真实比例字体与词框 NOT RUN |
| A06 | 快速A→B，故意让A后返回 | B不被A覆盖 | PASS（自动化：`TranslationCoordinatorTests.testSlowFirstResultCannotOverwriteSecond`，假提取器按代次乱序返回）；**真机 PASS（2026-09-17：快速换词卡片正确切换，用户确认）**；"慢结果晚到不覆盖"只有自动化证据 |
| A07 | 等待时松键、滚动、切应用 | 旧结果不复活 | PASS（自动化：`testReleaseBeforeResultDismissesAndLateResultIsIgnored`、`testExternalChangeInvalidatesOutstandingWork`；**真机 PASS（2026-09-17 用户确认："A07 没有问题"）**。此前"卡片不消失"的观察来自 Pin 状态卡片，属设计行为） |
| A08 | 原软件输入框正在输入 | 自动卡片不抢焦点、不吞按键 | NOT RUN（浮窗为 nonactivatingPanel 且按住时不显示按钮；需实机确认） |
| A09 | 松键后移入浮窗点击Pin | 卡片可固定；新悬停不覆盖 | 自动化部分 PASS（`CardLifecycleTests`、`testPinnedCardIsNotOverwrittenByNewHover`、`testPointerInsideTheCardPausesClosing`）；**真机 PASS（2026-09-17：松键后按钮出现且点击有效，用户确认）**；新悬停不覆盖 Pin 卡片未单独实测 |
| A10 | 屏幕角落/边缘 | 浮窗不越过可见区域、不遮挡目标 | 自动化部分 PASS（`CoordinateMapperTests` 含翻转、夹取、非零原点 visibleFrame）；多屏实机 NOT RUN |
| A11 | 密码/安全控件/来源未知 | 停止；不读取、不截图 | NOT RUN（代码对 AXSecureTextField/PID 不一致直接失败；需在真实密码框验证） |
| A12 | 退出和重新启动 | 无重复事件监视；允许列表和设置一致 | 部分 PASS（已实测真实 .app 启动并正常退出，无残留进程、无崩溃报告）；重复监视与设置持久化一致性 NOT RUN |

## B. v0.2

2026-09-17 v0.2 实施完成：自动测试 102/102 PASS（证据见 `docs/PROJECT_STATUS.md` 的"v0.2 实施会话"）。
下表"自动化"字样的行由可重复的单元测试覆盖；**真实 API 与 GUI 交互仍未执行**，需要用户自己输入 Key 并实机操作。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| B01 | 无API Key | 原文功能可用；提示配置，不伪造译文 | 自动化 PASS（`TranslationCoordinatorTests.testMissingKeyKeepsTheOriginalAndNamesTheFix`：0 次网络调用、卡片仍有原文、提示"add a DeepSeek API key in Settings to see Chinese"）；实机 NOT RUN |
| B02 | 用户输入Key并点击Test Connection | 只发送Open Settings；Key不进日志 | 部分自动化 PASS（`TranslationServiceTests.testRequestIsPostWithBearerKeyAndNoToolCalls` 校验 Authorization 头与请求体；Test Connection 的请求文本在代码里固定为 "Open Settings"，且此路径没有日志语句）；实机 NOT RUN（需用户输入 Key） |
| B03 | 假网络返回401/402/429/500/空响应/输出截断 | 正确分类；不把半段译文当完成；无无限重试或原始响应泄露 | 自动化 PASS（`testHTTPStatusMapping`、`testLengthFinishReasonIsTruncatedOutput`、`testEmptyChoicesIsInvalidResponse`、`testReasoningOnlyReplyIsNotASuccess`、`testBrokenJSONIsInvalidResponse`、`testFailureNeverCarriesTheRawResponseBody`、`testOfflineIsNetworkFailure`、`testTimeoutIsTimeoutFailure`、`testCancellationIsCancelledFailure`；402 归入 invalidResponse，已在文档说明） |
| B04 | 相同词相同上下文重复查询 | 命中内存缓存，不重复请求 | 自动化 PASS（`TranslationCacheTests.testInsertThenGetReturnsTheSameResult`、`TranslationCoordinatorTests.testCachedAnswerCostsNoSecondRequest` 断言请求数仍为 1）；实机 NOT RUN |
| B05 | charge在battery/service不同上下文 | 缓存不互相污染 | 自动化 PASS（`testContextAndModelArePartOfIdentity`、`testContextsDoNotContaminateEachOther`）；实机 NOT RUN |
| B06 | 慢请求中快速换词或松键 | 过期译文不显示 | 自动化 PASS（`testSlowFirstTranslationCannotOverwriteSecond`、`testReleasingTheTriggerDropsALateTranslation`——后者暴露并修复了"松键未失效 generation"的真实缺陷）；实机 NOT RUN |
| B07 | 选中英文后使用快捷键 | 翻译明确选区；失败引导粘贴 | 部分自动化 PASS（`TextInputPolicyTests` 覆盖长度/空白策略；**2026-09-18 整改轮**：`SelectionShortcutTests`（10 项）覆盖注册/冲突/释放，`TranslationCoordinatorTests` 覆盖焦点来源策略与读取失败；旧的 `SelectionShortcutController.matches` 已随事件监听器一并删除，本行证据随之更新）；实机 NOT RUN（见 F 组） |
| B08 | 自动查询前后比较剪贴板 | 不变；只有主动Copy可改变 | 部分自动化 PASS（`TranslationCoordinatorTests.testCopyIsOnlyEverTriggeredByTheUser`：自动查询后 copyCount 仍为 0，只有显式调用才写剪贴板）；实机 NOT RUN（需用户自查剪贴板） |
| B09 | 超过4000字符的粘贴 | 明确拒绝，不默默截断 | 自动化 PASS（`TextInputPolicyTests.testOverlongTextIsNotSilentlyTrimmed`、`TranslationCoordinatorTests.testManualTextIsRefusedBeforeItIsSent`：0 次网络调用并给出提示）；实机 NOT RUN |
| B10 | 删除Key/禁用来源/锁屏 | 按规格清缓存、取消并阻止新请求 | 自动化 PASS（`TranslationCacheTests` 的排除语义用例；**2026-09-18 整改轮**：`translationCredentialsChanged` / `translationPolicyChanged` / `sessionWentInactive` 都先使在途代次失效、取消任务，再清缓存——`testDeletingTheKeyDropsAnAnswerThatIsAlreadyInFlight`、`testExcludingTheSourceDropsAnAnswerThatIsAlreadyInFlight`、`testLockingTheSessionClearsTheCacheAndDropsInFlightWork`（锁屏后 `cache.count == 0`））；**真实锁屏触发路径实机 NOT RUN**（见 F09） |

## C. v0.3

2026-09-17 v0.3 实施完成：自动测试 **155/155 PASS**（证据见 `docs/PROJECT_STATUS.md` 的"v0.3 实施会话"）。
下表"自动化"字样的行由可重复的单元测试覆盖；**真实整句取词、真实屏幕录制授权后的截图 OCR、多屏摆放全部 NOT RUN**，
需要用户实机操作。OCR 相关的自动化证据分三类：纯策略/命中逻辑、**程序生成的合成英文图片**（真实 Vision，不是假识别器）、
以及注入假捕获的完整 extractor 路径——**没有**任何真实窗口截图证据。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| C01 | Option+Control指向两句中的一个词 | 只取包含该词的完整句子 | 自动化 PASS（`SentenceResolverTests.testOnlySentenceContainingTargetIsReturned`；`TranslationCoordinatorTests.testSwitchingToSentenceModeDropsTheWordRequest` 证明模式切换会失效旧词请求并改取整句）。**2026-09-18 变更**：修饰键由 Shift 改为 Control（用户要求），`TriggerPolicyTests` 与协调器测试同步改名/改断言；实机 NOT RUN |
| C02 | 缩写、跨行、列表、候选边缘 | 不可靠时明确partial | 自动化 PASS（**2026-09-20 重写**，见 J 组：`testAbbreviationDoesNotSplitTheSentence`、`testDecimalDoesNotSplitTheSentence`、`testDomainDotsDoNotSplitTheSentence`、`testASentenceWrappedOverTwoLinesIsReadWhole`、`testABlankLineIsNeverCrossed`、`testAListWithoutTerminatorsStaysPartial`、`testASentenceTouchingAClippedWindowStartIsPartial`、`testASentenceRunningPastAClippedWindowEndIsPartial`、`testAFragmentWithoutATerminatorIsPartial`；边界类别也逐条断言）。**旧断言"硬换行必然断句"的 `testHardLineBreakBoundsTheSentence` 已按新设计删除**（单个换行现在被视为排版换行）；实机 NOT RUN（见 J 组） |
| C03 | AX可读正文，OCR开关也开 | 不无谓调用截图 | 自动化 PASS（OCR 只在 AX 抛出 `.noText`/`.notSupported`/`.positionUnresolved` 后才可能启动，成功路径不增加 `ocrStarts`：`testAPolicyRefusalNeverStartsACapture`、`testIdleCountersDoNotGrowWithoutATrigger`）；**实机截图调用计数 NOT RUN** |
| C04 | 合成图片英文，已允许OCR | 本机识别词框，显示OCR来源 | 自动化 PASS（`OCRImageTests` **10 项**：程序生成的英文图片经真实 Vision 得到逐词框，extractor 返回 `source: .ocr`、词框落在截图区域内；句子模式在截图中**无法证明边界时标 partial**（`testExtractorReturnsAPartialSentenceForTheHitLine`、`testASentenceStartingAtTheCaptureEdgeIsPartial`），**能证明时标 complete**（`testASentenceWrappedOverTwoLinesIsReadWhole`，2026-09-20 新增）；另有脚本化识别验证跨行锚点覆盖两行词框）；**真实窗口截图 NOT RUN（需用户授予屏幕录制权限）** |
| C05 | 拒绝捕获权限/命中敏感控件 | 截图调用计数0，不绕过 | 自动化部分 PASS（`testSecurityDenialNeverBecomesScreenshotFallback`、`testPolicyFailuresNeverReachTheScreen`、`testTheFallbackNeedsBothTheSwitchAndThePermission`、`OCRImageTests.testAnUnconfirmedWindowNeverCapturesAnything`：捕获调用次数实测为 0）；**实机截图调用计数 NOT RUN** |
| C06 | 空白、小字、低置信度 | 不猜一个词当正确答案 | 自动化 PASS（`OCRHitTesterTests.testWhitespaceDoesNotPickNearestWord`、`testLowConfidenceIsNeverAnAutomaticAnswer`、`testHitToleranceIsTwoScreenPoints`；`OCRImageTests.testWhitespaceProducesNoOCRResult` 用真实识别结果验证空白处返回 `.noText`）；实机小字 NOT RUN |
| C07 | 双栏和局部截断 | 不串栏，不补写原文 | 自动化 PASS（`testLineRunStopsAtAColumnGap` 加上 **2026-09-20 新增** `testTwoColumnsAreNeverJoined`、`testATableIsNeverJoinedAcrossCells`、`testASentenceIsNeverJoinedToFarAwayText`、`testALargeVerticalGapStopsTheContext`、`testTheContextIsBoundedByItsLineLimit`：间隙、行带、行距、水平跳跃任一不满足就断开，最多 6 行；OCR 只有在截图内能证明左右边界时才标 complete，否则 partial；系统提示词仍要求不补写、不执行嵌入指令）；实机 NOT RUN（见 J 组） |
| C08 | 浮窗曾在同一区域显示 | OCR不识别本工具卡片 | 结构性保证（捕获过滤器 `SCContentFilter(desktopIndependentWindow:)` 只包含已确认的源窗口，本工具浮窗属于另一个窗口，因此不在帧内）；**未实机取证** |
| C09 | Retina/缩放/左侧或上方外接屏 | 坐标正确；无设备则明确未测 | 自动化部分 PASS（`CoordinateMapperTests` 新增 11 项：1x/2x 像素尺寸、400 万像素上限且保持比例、负坐标外接屏、窗口内夹取、归一化词框映射、窗口局部 sourceRect）；**本机无外接屏，实机多屏 NOT RUN** |
| C10 | OCR或网络中途取消 | 释放截图；迟到内容不显示 | 自动化 PASS（`testReleasingTheTriggerDropsALateOCRResult`、`testASlowOCRResultCannotOverwriteANewerHover`、既有 `testSlowFirstTranslationCannotOverwriteSecond`：三层任一迟到都不复活旧卡片；位图只被 `CapturedFrame` 持有，extract 返回或抛错即释放，不写文件）；实机 NOT RUN |
| C11 | 静置未触发 | 无持续录屏、识别、联网 | 自动化 PASS（`testIdleCountersDoNotGrowWithoutATrigger`：未按触发键时提取 0 次、捕获 0 次、翻译 0 次；OCR 使用单帧 API，代码里不存在持续流）；**实机截图调用计数 NOT RUN** |

## D. v0.4

2026-09-17 v0.4 实施完成：自动测试 **182/182 PASS**（证据见 `docs/PROJECT_STATUS.md` 的"v0.4 实施会话"）。
Release 0.4 构建、签名、复制件启动均已实测。下表"自动化"字样的行由可重复的单元测试覆盖；
**真机 UI 操作（真机保存→重启→查看、深色外观、菜单栏交互）仍为 NOT RUN**，需要用户执行。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| D01 | 普通查询/固定卡片 | 不自动保存生词 | 自动化 PASS（`TranslationCoordinatorTests.testAHoverNeverSavesAnythingUntilTheUserClicks`：悬停、翻译完成、Pin 之后收藏文件仍为空）；实机 NOT RUN |
| D02 | 主动收藏并重启 | 只保留已收藏内容 | 自动化 PASS（`LearningStoreTests.testExplicitSaveAndDeleteRoundTrip`、`testEntriesAndTheirIdentitySurviveARestart`：新的 store 实例读回同样条目与 id/日期）；**真机 UI 重启往返 NOT RUN** |
| D03 | 同词不同上下文 | 可以独立保存和删除 | 自动化 PASS（`testTheSameSourceWithADifferentContextIsKeptSeparately`：两条独立条目，删一条不影响另一条） |
| D04 | 不点击Explain | 没有解释网络请求 | 自动化 PASS（`testNothingIsExplainedWithoutAClick`、`testExplainIsIgnoredWhileTheTriggerIsStillHeld`：provider 收到的请求数实测仍为 1，只有 hover 自己那一次） |
| D05 | 收藏文件损坏 | 提示错误，不静默覆盖数据 | 自动化 PASS（`testACorruptFileIsReportedAndNeverOverwritten`：`all()`/`save()` 均抛 `.unreadable` 且文件内容逐字节不变；`testASavedFileThatCannotBeReadIsNeverOverwritten` 覆盖到协调器与卡片提示；`testClearingRecoversFromACorruptFile` 覆盖显式恢复） |
| D06 | 清缓存/删Key/删收藏 | 真实执行，并可验证 | 自动化 PASS（`testClearingTheCacheMakesTheNextQueryCostARequestAgain`：清空返回条数、actor 内计数为 0、同一查询重新发请求；`testDeletingTheKeyStopsFurtherExplanations`：删 Key 后不再联网；`testClearingRecoversFromACorruptFile` 覆盖删收藏）；实机 NOT RUN |
| D07 | 实际Release app启动 | 菜单栏与核心功能可用 | 部分 PASS（Release 构建退出码 0、`codesign --verify --deep --strict` 通过、**复制件实测启动并稳定运行 12 秒无崩溃报告**、版本 0.4/build 4）；菜单栏与核心功能需用户操作）；实机交互 NOT RUN |
| D08 | 深浅色/长句/较大字号 | 内容可读，不溢出 | NOT RUN（卡片、收藏窗口与设置只用语义色/材质并允许换行；没有自动截图手段，"较大字号"需要用户在自己机器上确认） |
| D09 | 完整回归A/B/C | 没有新引入的核心回归 | 部分 PASS（自动测试 182 项全绿，v0.1–v0.3 的用例全部保留并继续通过；A/B/C 的真机项仍为 NOT RUN） |

## E. v0.5（用户要求的"全局可用"后置变更）

2026-09-18：用户要求"任何应用都能取词，不再逐个添加允许列表"，`SourcePolicy` 由**允许列表**改为**排除列表**（默认空）。
自动测试 188/188 PASS。旧允许列表的 UserDefaults 键保留但不再读取。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| E01 | 排除列表为空时悬停任意应用 | 直接取词，不需要先添加 | 自动化 PASS（`testEveryApplicationIsReadWithoutAnExclusionList`、`SourcePolicyTests.testAnEmptyExclusionListReadsEveryApplication`）；实机 NOT RUN |
| E02 | 把某应用加入排除列表后悬停 | 该应用不读取；其它应用不受影响；缓存也不复用它的答案 | 自动化 PASS（`testAnExcludedApplicationIsNeverRead`、`SourcePolicyTests.testAnExcludedApplicationIsDenied`、`TranslationCacheTests.testAnExcludedOrUnknownSourceCannotReadTheCache`、`testEntriesForExcludedSourcesAreDropped`）；实机 NOT RUN |
| E03 | 指向没有 bundle ID 的来源 | 仍然拒绝（无法归属，也就无法与排除列表比对） | 自动化 PASS（`testASourceWithoutABundleIdentifierIsRefused`、`SourcePolicyTests.testAnUnattributedSourceIsAlwaysDenied`） |
| E04 | 从 v0.4 升级（旧允许列表里有应用） | 旧列表不被当成排除列表 | 自动化 PASS（`SettingsStoreTests.testTheOldAllowListIsNeverReadAsAnExclusionList`：旧键写入后 `excludedBundleIDs` 仍为空） |
| E05 | 排除的应用 + OCR 开关都满足 | 排除仍然优先：不取词也不截图 | 自动化 PASS（排除在取词之前就返回，永远到不了 OCR 分支；`testAnExcludedApplicationIsNeverRead` 断言 0 次取词）；实机截图计数 NOT RUN |

## F. 2026-09-18 整改轮（阅读边界、剪贴板、快捷键注册、缓存失效）

2026-09-18：依据外部只读审阅 `docs/PROJECT_REVIEW_2026-09-18.md` 的 R1–R7 完成整改；自动测试 **205/205 PASS**，
Release 构建、签名与复制件启动已实测。下表"自动化"行由可重复单元测试覆盖；**真机项（R8）全部 NOT RUN**。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| F01 | 鼠标在 A 应用、键盘焦点在 B 应用时按选区快捷键 | 按 B 的来源策略执行；不会把鼠标下的 A 当作选区来源 | 自动化 PASS（选区来源取自焦点 AX 元素的 PID：`testAnAllowedSelectionIsReadAndTranslated`、`testSelectionFromAnExcludedApplicationIsNeverRead`）；实机 NOT RUN |
| F02 | 被排除应用 / 无法归属来源 / 密码框里按快捷键 | 选区正文读取 0 次、网络 0 次，并提示原因 | 自动化 PASS（`testSelectionFromAnExcludedApplicationIsNeverRead`、`testSelectionFromAnUnknownSourceIsRefusedBeforeTheBodyIsRead`、`testSelectionFromASecureControlIsRefusedBeforeTheBodyIsRead` 断言 `bodyReadCount == 0` 且 `requestCount == 0`）；实机 NOT RUN |
| F03 | 读取期间切换焦点或被加入排除列表 | 迟到选区不展示、不发送 | 自动化 PASS（`testASelectionReadIsDroppedWhenTheSourceIsExcludedMeanwhile`；extractor 层用 PID 核对，不一致返回 nil）；实机 NOT RUN |
| F04 | 打开手动窗口（菜单入口或选区失败） | 剪贴板读取 0 次；输入框为空并提示粘贴 | 自动化部分 PASS（自动读取剪贴板的代码已删除，全库只剩 Copy 写剪贴板；`promptForManualPaste` 打开空编辑器）；**实机自查剪贴板 NOT RUN** |
| F05 | 同时存在悬停卡片与手动译文时分别点 Copy | 各复制各自内容 | 自动化 PASS（`testTheManualCopyButtonCopiesTheManualResult` 直接调用 `ManualActionWiring.wire` 后点 Copy：手动 presenter +1、悬停 presenter 0）；实机 NOT RUN |
| F06 | 快捷键组合已被其它应用注册 | 菜单与设置提示冲突并建议换一个 | 自动化部分 PASS（`SelectionShortcutController.state(for:)` 把 `eventHotKeyExistsErr` 映射为 `.conflict`，文案由 `summary(label:canReadSelection:)` 统一）；**实机冲突提示 NOT RUN（本机无冲突对象）** |
| F07 | 切换预设、退出应用 | 旧组合被释放，退出不留注册 | 自动化 PASS（`testChangingThePresetRegistersTheNewOneAndReleasesTheOld`、`testStoppingReleasesTheCombination`）；实机 NOT RUN |
| F08 | 同一次按键 | 只触发一次选区读取 | 自动化部分 PASS（`testOneShortcutPressStartsExactlyOneSelectionRead` 直接调用注册回调：只启动一次读取；注册只有一个 handler，不再有事件监听器）；**真实按键投递到 handler 未实机验证** |
| F09 | 请求在途时删 Key / 排除来源 / 关闭云端翻译 / 锁屏 / 手动清缓存 | 旧结果不展示、不重新写缓存；锁屏后缓存计数 0 | 自动化 PASS（`testDeletingTheKeyDropsAnAnswerThatIsAlreadyInFlight`、`testExcludingTheSourceDropsAnAnswerThatIsAlreadyInFlight`、`testTurningTranslationOffDropsAnAnswerThatIsAlreadyInFlight`、`testLockingTheSessionClearsTheCacheAndDropsInFlightWork`；手动清缓存走同一个失效入口）；实机锁屏路径 NOT RUN |
| F10 | 阶段耗时日志 | 能读到阶段名与整数毫秒，且不含原文/译文/Key/路径/窗口标题 | 部分 PASS（被测试进程的实时日志实测 `stage=accessibility gen=1 ms=0 outcome=success`、`stage=explanation ...`；字段只有阶段/generation/ms/outcome）；性能样本 NOT RUN |
| F11 | 整改后的完整自动回归 | 没有引入核心回归 | 部分 PASS（自动测试 205 项全绿，v0.1–v0.5 的用例全部保留；A–E 的真机项仍为 NOT RUN） |

## I. v0.7 单词的词性与多个意思（离线词库）

依据 `docs/THIRD_PARTY_NOTICES.md` 与 `docs/RELEASE_NOTES.md` 的 v0.7 条目。自动化由 `WordBookTests` 与两条协调器测试覆盖；
**真机项全部 NOT RUN**，只能由用户本人操作，不预填 PASS。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| I01 | 悬停一个常见单词（`run`、`open`、`button`） | 卡片出现 `Dictionary · On-device`，按词性依次列出（`n.` / `vi.` / `vt.` …） | 自动化 PASS（`WordBookTests` 的解析与上限用例）；实机 NOT RUN |
| I02 | 有多种词性的词（`open` 有 5 个词性） | 最多显示 3 个词性、每个 1 条意思；还有更多时末尾显示 `…` | 自动化 PASS（`testPartsOfSpeechAreListedInSourceOrder`、`testAWordWithThreePartsOfSpeechShowsOneGlossEach`）；实机 NOT RUN |
| I03 | 一个词性有多个意思 | 同一词性最多 2 条；两个词性时前一个拿多出来的一条 | 自动化 PASS（`testAShortEntryIsNotMarkedTruncated` 里的两词性断言）；实机 NOT RUN |
| I04 | `[计]` / `[法]` 这类语域行 | 作为独立分组显示，标签不丢 | 自动化 PASS（`testARegisterLabelIsItsOwnGroup`）；实机 NOT RUN |
| I05 | 变形词（`settings`、`charges`、`children`） | 有独立词条就用它，否则经"变形 → 原型"映射回原型 | 自动化 PASS（`testAnInflectedFormResolvesToItsLemma`、`testTheBundledWordbookAnswersForTheCommonCase`）；实机 NOT RUN |
| I06 | 悬停整句 / 短语 / 按钮标签 | **不**查词库，卡片不出现词典段 | 自动化 PASS（`testASentenceIsNotLookedUpInTheWordbook`、`testAnEmptyOrBlankWordHasNoEntry`）；实机 NOT RUN |
| I07 | 词库里没有的词 | 卡片只显示译文，不显示空的词典段 | 自动化 PASS（`testAnUnknownWordHasNoEntry`）；实机 NOT RUN |
| I08 | 断网时悬停单词 | 词性释义照常出现（纯本地文件）；译文按所选引擎的规则 | 实机 NOT RUN（需要用户断网操作） |
| I09 | 来源标识与文案 | 词典段标 `Dictionary · On-device`，与译文来源分开，不冒充 AI 解释 | 实机 NOT RUN |
| I10 | 悬停单词后立刻移开 / 松键 | 迟到的词库结果不写进新卡片（沿用代次门） | 自动化 PASS（`requestDictionaryEntry` 只在 `shownSnapshot?.generation` 相同时下发；`FloatingPanelController.setDictionary` 再按 `sessionID` 校验）；实机 NOT RUN |

### I 组手动验收步骤（需要用户本人操作）

1. 重新构建后打开 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`。
2. **主链（I01/I02/I03）**：在 TextEdit 里分别悬停 `run`、`open`、`button`、`charge`。期望：卡片上先出现英文原文，
   随后出现 `Dictionary · On-device` 一段，按词性依次列出（如 `n. 跑, 赛跑` 换行 `vi. 跑`），最多 3 条意思，多出来的用 `…` 表示。
3. **变形词（I05）**：悬停 `settings`、`children`、`committed`。期望：都能给出释义（先查自身词条，再回原型）。
4. **不越界（I06/I07）**：悬停整句、悬停一个生僻词或专有名词。期望：整句不出现词典段；生僻词只显示译文，不留空标题。
5. **断网（I08）**：关掉 Wi-Fi 后悬停 `open`。期望：词性与释义照常出现。
6. **来源标识（I09）**：确认词典段的标题是 `Dictionary · On-device`，与译文、AI 解释三段互不混淆。


## J. 2026-09-20 网页命中可靠性与跨行整句

依据 `docs/superpowers/specs/2026-09-19-web-hit-and-cross-line-sentence-design.md` 的 §3/§4 与 §7。
自动化由 `SentenceResolverTests`（26 项：规范化、双向偏移映射、缩写/小数/域名/中文标点/引号/emoji、窗口裁切与边界类别）、
`AccessibilityTextExtractorTests`（新增短控件与整句用例）、`OCRHitTesterTests`（15 项）、`OCRImageTests`（10 项，含真实 Vision 的两行整句）
覆盖；**实机项全部 NOT RUN**，只能由用户本人操作，不预填 PASS。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| J01 | Google Workspace 顶部导航，指针停在 `Solutions` 文字的笔画上 | 卡片显示 `Solutions`（`label · whole control`） | 实机 NOT RUN |
| J02 | 同一个控件，指针停在它自己的内边距上（文字左/右/上下的留白） | 与 J01 **同一个标签**——这正是本轮要消除的"有时能翻、有时不能" | 实机 NOT RUN |
| J03 | 在同一个短控件上左右轻微移动指针 | 结果不随位置改变；不再出现 `no readable text at this position` | 实机 NOT RUN |
| J04 | 悬停普通正文链接与正文静态文本 | 与修复前一致（`label`），没有因为新增"直接子节点"读取而改变范围 | 实机 NOT RUN |
| J05 | 网页正文里跨两行/三行的英文句子（触发键 + Control） | 原文从上一句末标点之后到本句句末标点（含引号/括号）完整一致，折行处是空格而不是断句 | 实机 NOT RUN |
| J06 | 段落最后一行没有句号、或句子被读取窗口边缘截断 | caption 出现 `partial — select the full sentence to translate all of it` | 实机 NOT RUN |
| J07 | 空行分隔的两个段落 | 不跨段：只读指针所在那一段的句子 | 实机 NOT RUN |
| J08 | 双栏正文/表格页面，指针在一栏或一个格子里 | 不串栏、不串行；读不到完整句子时是 partial，而不是把两栏拼成一句 | 实机 NOT RUN |
| J09 | 短按钮、菜单项（含右键菜单） | 仍然得到整个标签，没有回归 | 实机 NOT RUN |
| J10 | 短控件**不报矩形**、或指针不在其矩形内的应用 | 明确失败提示（可能进入 OCR 兜底），不猜一个邻近标签；这条是设计 §3.2 新增的前置条件，属于**行为变化** | 实机 NOT RUN |

### J 组手动验收步骤（需要用户本人操作）

1. 确认运行的是本轮构建的产物：`$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`（0.7/7）。
2. **导航（J01–J03）**：打开 Google Workspace（或任意 Chrome 页面）顶部导航，把指针分别停在 `Solutions` 的字母上、
   以及它的左侧与上下留白上，各停 250 ms。期望三处给出同一个标签 `Solutions`，不再出现 `no readable text at this position`。
3. **正文整句（J05–J07）**：找一段有两个句子、且第一句折行的英文，按住触发键 + Control 悬停在第一句中间的词上。
   期望卡片原文从上一句末标点之后开始、到本句句末标点（含引号/括号）结束，折行处是一个空格。
   再把指针移到段落最后一行（没有句号）重复一次，期望出现 partial 提示，而不是把后面的句子拼进来。
4. **排版边界（J08）**：在双栏页面（例如维基百科）与一个表格页面上重复第 3 步。期望不跨栏、不跨表格行。
5. **回归（J04/J09）**：在正文链接、正文静态文本、一个短按钮与一个菜单项上各悬停一次，期望与之前相同；
   单词入口、选区入口、OCR 限流都不受影响。
6. **诊断日志（可选）**：`log stream --style compact --level debug --predicate 'subsystem == "com.atat.HoverTranslate"'`
   应能看到 `short control role=… origin=…` 与 `sentence boundary=…` 两类**类别**行；日志里不应出现任何正文、URL 或坐标。

## G. v0.6 悬停已选中文本（按住触发键把指针移到选区上）

依据 `docs/superpowers/plans/2026-09-18-v0.6-hover-selection.md` 的 §3 判定规则表与 §6.2 手动矩阵。
"自动化"行由可重复单元测试覆盖（`SelectionHitPolicyTests`、`AccessibilityTextExtractorTests` 的选区探测用例、
`TranslationCoordinatorTests.testAHoveredSelectionBecomesOneSelectionRequest`）；**真机项全部 NOT RUN**，
只能由用户本人操作，不预填 PASS。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| G01 | TextEdit：选中一整句 → 按住触发键把指针移到选区上停住 | 浮窗出现，原文＝完整选区文本，随后出现中文；全程不按任何快捷键、不写剪贴板 | 实机 NOT RUN |
| G02 | 指针停在选区**之外**的文字上 | 仍按原规则取词/取句，不翻译选区 | 自动化 PASS（`testAPointerOutsideTheSelectionStillTranslatesTheWordUnderIt`、`testTheIndexTestRejectsAPointerInTheUnionRectOfAMultiLineSelection`）；实机 NOT RUN |
| G03 | 没有选中任何文本 | 与现状完全一致（单词 / 触发键+Control 整句） | 自动化 PASS（`testWithoutASelectionTheHoverPathIsUnchanged`）；实机 NOT RUN |
| G04 | 被排除的应用里选中英文后悬停 | 不读取、不发送、不显示任何内容 | 自动化 PASS（既有来源策略测试：排除来源在取词之前就被拒绝，读取层根本进不到）；实机 NOT RUN |
| G05 | 密码框 / 安全控件 | 不读取选区正文（沿用现有拒绝） | 自动化 PASS（`testAProtectedFocusedControlIsNeverRead` 断言选区正文读取 0 次）；实机 NOT RUN |
| G06 | 选区超过 4000 字符（整篇文档） | 不发送、不截断；回落为指针处单词 | 自动化 PASS（`testAnOverLongSelectionIsRefusedInsteadOfTruncated`）；实机 NOT RUN |
| G07 | 选区内按住 Control 悬停 | 结果仍是整段选区（选区优先于整句模式） | 自动化 PASS（`testASelectionWinsEvenWhenTheSentenceModifierIsHeld`）；实机 NOT RUN |
| G08 | 命中后立刻松键，结果仍在途 | 迟到结果不显示（沿用现有代次规则） | 自动化 PASS（既有 `testReleaseBeforeResultDismissesAndLateResultIsIgnored`，本版按计划不重复造）；实机 NOT RUN |
| G09 | 逐一登记 TextEdit / 日常用的第二个应用 / Safari / PDF 阅读器 | 记录该应用是否提供 `AXSelectedTextRange`、`AXBoundsForRange`、`AXRangeForPosition`；不提供的记 NOT SUPPORTED | 实机 NOT RUN |
| G10 | 回归：Control-Command-T 选区快捷键 | 行为与 v0.5 完全一致（焦点控件来源 + 手动窗口） | 自动化 PASS（既有 `SelectionShortcutTests` 全绿，本版未改该入口）；实机 NOT RUN |
| G11 | 悬停延迟 | 用 `stage=accessibility gen=<n> ms=<n>` 日志对比改动前后（同一应用、同一句），记录实际毫秒数，不给结论性承诺 | 实机 NOT RUN |

### G 组手动验收步骤（需要用户本人操作）

1. 重新构建后打开 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`，确认菜单栏只有一个图标。
2. **主链（G01）**：TextEdit 里输入一整句英文 → 选中它 → 按住触发键（默认右 Option）把指针移到选区内停住。
   期望：约 250 ms 后浮窗出现，原文逐字符等于选区文本，随后出现中文译文；全程不按快捷键、不写剪贴板。
3. **回落（G02/G03/G06）**：把指针移到选区外的单词上；再取消选区后悬停；再用整篇超长文档做一次超过 4000 字符的选区。
   期望：前两种走原来的单词/整句路径；超长选区不发送、不截断，回落为指针处单词。
4. **拒绝（G04/G05）**：在排除列表里的应用、以及密码框内重复悬停。期望：不读取、不发送、不显示任何内容。
5. **选区优先（G07）**：在选区内同时按住 Control 悬停。期望：结果仍是整段选区，不是单句。
6. **迟到结果（G08）**：命中后立刻松键。期望：不出现迟到结果，浮窗不复活。
7. **应用能力登记（G09）**：对 TextEdit、你日常用的第二个应用、Safari、PDF 阅读器逐个试一次，记录该手势是否生效；
   不生效的应用记 NOT SUPPORTED，并确认此时仍可用 Control-Command-T。
8. **延迟（G11）**：同一应用、同一句，对比改动前后的 `stage=accessibility gen=<n> ms=<n>` 日志，只记录实测毫秒数。

## H. 2026-09-18 悬停可靠性修复（诊断文档 R1–R4）

依据 `docs/HOVER_RELIABILITY_DIAGNOSIS_AND_FIX_PLAN_2026-09-18.md`。本轮自动测试 **226 passed / 0 failed / 0 skipped**
（2026-09-18 实测，日志 `.build/final-reliability-test.log`；历史文档里的 205/205 是上一轮结果，**不代表本轮**）。
"自动化"行由可重复单元测试覆盖；**真机项全部 NOT RUN**。

| ID | 操作/情境 | 期望 | 状态 |
|---|---|---|---|
| H01 | 主屏顶/中/底，以及上方/左侧副屏上悬停 | 传给 AX 命中接口与字符定位的是**同一个 AX 坐标**（只转换一次） | 自动化 PASS（`AccessibilityTextExtractorTests`：`testTheHitIsAskedForTheAXPointAndNotTheAppKitPoint`、`testTheCharacterLookupUsesTheSameConvertedPoint`、`testTheConversionCoversTopMiddleAndBottomOfThePrimaryScreen`、`testPointsOnASecondaryScreenAboveOrLeftOfThePrimaryKeepTheirOffset`）；实机 NOT RUN |
| H01r | 同一缺陷的"红"证据 | 把转换去掉后这四条真的失败 | 实测：临时还原缺陷后 **TEST FAILED**（日志 `.build/r1-red-proof.log`），随后恢复 |
| H02 | 来源不符 / 密码控件 / 无辅助功能权限 | 正文读取 0 次；策略失败不进入 OCR | 自动化 PASS（`testASourceMismatchIsRefusedBeforeAnyTextIsRead`、`testAProtectedControlIsRefusedBeforeAnyTextIsRead`、`testWithoutAccessibilityPermissionNothingIsAskedOfTheSystem` 断言 `textReads == 0`；`testAControlWithNoPositionMappingIsNotSupportedSoOCRMayStillBeConsidered` 与既有 `testAPolicyRefusalNeverStartsACapture` 保留"只有 notSupported/positionUnresolved/noText 可兜底"） |
| H03 | 两次查询间隔不足 800 ms，指针不动 | 第二次进入**等待**，到期只补试一次并显示结果 | 自动化 PASS（`testARateLimitedQueryIsRetriedOnceTheIntervalHasPassed`：等待时 status 为"正在识别"，`lastFailure` 仍为 nil，tick 到期后 `ocrStarts == 2` 且结果用同一 generation 显示） |
| H04 | 等待期间移动 / 松键 / 切换来源 / 被加入排除列表 | 旧任务不截图、不显示迟到结果 | 自动化 PASS（`testADeferredCaptureNeverFollowsThePointerToANewPosition`、`testAPendingCaptureIsDroppedWhenTheTriggerIsReleased`、`testAPendingCaptureIsDroppedWhenTheSourceIsNoLongerTheSameWindow`、`testAPendingCaptureIsDroppedWhenTheApplicationIsExcludedMeanwhile`） |
| H05 | OCR 关闭 / 未授权 / 已有 OCR 未结束 | 不安排补试；限流到期也不重叠第二个实际截图 | 自动化 PASS（`testNoCaptureIsDeferredWithoutTheSwitchOrThePermission`、`testADeferredCaptureNeverOverlapsACaptureThatIsStillRunning` 断言 `ocrStarts == 1`） |
| H06 | 无文字 / 被拒 / 等待识别 | 简短原因或"recognizing…"，不是静默；同一句被节流，逾期自动消失 | 自动化 PASS（`testAnUnreadableHoverStatesTheReasonInsteadOfShowingNothing`、`testTheSameStatusIsThrottledAndThenGoesAwayOnItsOwn`）；实机文案与摆放 NOT RUN |
| H07 | 补试失败或无法满足前置条件 | 保持有界：不再排第二次补试 | 自动化 PASS（补试只在失败路径安排一次，`retryDeferredOCRIfDue` 先清空待办再核对；无法满足即丢弃，日志记 "deferred capture was dropped"） |
| H08 | 未触发 | 零提取、零 OCR、零联网 | 自动化 PASS（既有 `testIdleCountersDoNotGrowWithoutATrigger` 全绿） |
| H09 | 失败原因的可诊断性 | 日志能区分"没触发 / AX 失败（含 role 与映射类别）/ 等 OCR / OCR 无命中"，且不含正文 | 部分 PASS（新增 `hit role=… mapping=…` 与 `extraction failed reason=…`；真实 Chrome 页面样本 NOT RUN） |

### H 组手动验收步骤（需要用户本人操作）

1. **R1 主验收（H01）**：打开 Chrome，把窗口分别放在屏幕顶部、中部、底部，在**同一次**会话里悬停已知英文；
   期望浮窗里的原文就是指针所指的那个词（不是别处、也不是别的按钮标签）。然后在副屏（上方或左侧）复测一次。
2. **R3 证据采集**：在一处悬停无反应的文字上停下，运行
   `log stream --predicate 'subsystem == "com.atat.HoverTranslate"'`，记录该次输出的 `hit role=… mapping=…` 与
   `extraction failed reason=…`（**只记类别，不要复制网页正文**）。分别记录：网页内部导航链接、Chrome 标签栏/工具栏/书签栏、
   macOS 系统菜单栏。支持不了的类别如实记 NOT SUPPORTED，不改动浏览器辅助功能配置。
3. **R2 补试（H03）**：开启 OCR 兜底并授予屏幕录制后，快速从图片上的词 A 移到词 B 并静止；期望先出现"recognizing…"，
   随后自动补试一次并显示结果（不是一直没反应）。
4. **取消（H04）**：在"recognizing…"期间松键、滚动或切换到别的应用；期望不再弹出任何卡片或状态，也没有旧窗口的截图。
5. **失败反馈（H06）**：悬停在空白处或受限控件上；期望出现一条简短状态（如 `no exact text at this position`），
   约 1.4 秒后自行消失，不抢焦点、不遮挡鼠标位置。
6. **固定卡片**：Pin 一张卡片后再悬停别处；期望固定卡片不被状态或新结果覆盖。
7. **多屏（H01）**：若有外接屏，把窗口放在主屏上方/左侧的屏上复测命中与浮窗位置。

## 真实软件兼容矩阵

以下是候选测试对象，不是已验证支持清单。使用用户实际安装的软件和版本。
2026-09-17：全部仍未实测，等待用户授予辅助功能权限后逐项操作。

| 软件/版本 | AX单词 | AX标签 | 选区 | 整句 | OCR | 实测日期/屏幕配置 |
|---|---|---|---|---|---|---|
| TextEdit | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测 |
| 系统设置 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测 |
| 用户实际浏览器（正文 顶/中/底） | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测（2026-09-18 修复 R1 坐标缺陷后需重测） |
| 网页内部导航链接 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测（R3：需先采集 role 与映射类别） |
| Chrome 标签栏/工具栏/书签栏 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测（R3：与网页内容分属不同 AX 层级） |
| macOS 系统菜单栏 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测（R3：可能需要独立的窗口层级归属处理） |
| 用户实际英文AI客户端 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测 |
| Xcode/用户编辑器 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测 |
| 用户实际终端 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | 未测 |
| 自制合成英文图片 | NOT APPLICABLE | NOT APPLICABLE | NOT APPLICABLE | NOT RUN | 自动化 PASS（合成图片经真实 Vision，非真实窗口） | 2026-09-17 自动测试 |

## 性能记录

只记录实际测量值与样本数：AX提取、OCR、API、cache、端到端分别计时。
250ms触发等待不等于翻译延迟。不要给没有样本支持的"秒开""实时p95"等结果。
失败案例需写复现步骤、预期/实际、调用阶段与修复状态；不附用户敏感画面或原文。

2026-09-17：v0.1 未做性能测量（只有构建/测试时长）。首次 AX 实测后再补样本。

2026-09-17 v0.3：代码已按阶段记录 `stage=accessibility|ocr|cache|translation gen=<n> ms=<n> outcome=<类别>`
（只有阶段名、generation、毫秒数与结果类别，**不含原文、译文、图片、窗口标题或路径**；见 `TranslationCoordinator.logTiming`）。
**尚未采集任何真实样本**：本次只执行了自动测试，测试使用固定注入时钟且不做性能断言，因此**不提供任何延迟结论**。
可用下面的方式在实机采集（只输出数字与类别名）：

```bash
log stream --predicate 'subsystem == "com.atat.HoverTranslate"' --info --debug
```

## v0.1 自动测试证据（可重复）

```bash
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" test
# 2026-09-17 实测：退出码 0，49 passed / 0 failed
```

测试类：`TriggerPolicyTests`、`HoverDwellTests`、`TextResolverTests`、`CoordinateMapperTests`、
`RequestGateTests`、`SourcePolicyTests`、`CardLifecycleTests`、`TranslationCoordinatorTests`。
单个类可用 `-only-testing:HoverTranslateTests/<类名>`。

## v0.2 自动测试证据（可重复）

```bash
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test
# 2026-09-17 实测：退出码 0，**102 passed / 0 failed**（xcresult: total 102, failed 0, skipped 0）
```

不得把 DerivedData 放进项目目录：iCloud/FileProvider 会在 Strip 脚本之后写回 Finder 属性，CodeSign 会以
`resource fork, Finder information, or similar detritus not allowed` 失败（本次实测）。

v0.1 已有的 8 个测试类全部保留并通过；v0.2 新增：`TranslationRequestBuilderTests`、`TranslationServiceTests`、
`TranslationCacheTests`、`TextInputPolicyTests`、`KeychainStoreTests`。

## v0.3 自动测试证据（可重复）

```bash
cd "/path/to/HoverTranslate_Execution_Pack"
# 红 → 绿：先只有测试、实现不存在时退出码 65（cannot find type ... in scope）
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test
# 2026-09-17 实测：退出码 0，TEST SUCCEEDED
# xcresult 实读：passedTests 155, failedTests 0, skippedTests 0, expectedFailures 0
```

v0.3 新增测试类：`SentenceResolverTests`(12)、`OCRFallbackPolicyTests`(5)、`OCRHitTesterTests`(7)、`OCRImageTests`(7)；
`CoordinateMapperTests` 6→17、`TranslationCoordinatorTests` 17→26、`TriggerPolicyTests` 7→9。
单个类可用 `-only-testing:HoverTranslateTests/<类名>`。

`OCRImageTests` 的图片由测试自己用 CoreText 画到 `CGContext` 上（黑字白底、比例字体），**不使用任何真实桌面截图**；
它跑的是真实 Vision 识别链，只有"捕获"这一步被注入的假实现替换。

## v0.4 自动测试与 Release 证据（可重复）

```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates test
# 2026-09-17 实测：退出码 0；xcresult 实读 passedTests 182, failedTests 0, skippedTests 0

xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Release -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates build
# 2026-09-17 实测：退出码 0，本项目源码 0 warning
# 产物：$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app
#   CFBundleShortVersionString 0.4 / CFBundleVersion 4 / 3.4 MB；codesign --verify --deep --strict 通过
```

v0.4 新增测试类：`LearningStoreTests`(7)、`ExplanationRequestBuilderTests`(4)、`SelectionShortcutTests`(5)；
`TranslationCoordinatorTests` 26→34、`TranslationServiceTests` 16→18。

**注意**：计划文档里的 Release 命令用 `-derivedDataPath .build/DerivedData`（项目目录内）。本机实测该路径下
"构建成功但产物签名无效"（iCloud/FileProvider 在签名后写回 `com.apple.FinderInfo`，`codesign --verify` 报
`resource fork, Finder information, or similar detritus not allowed`）。DerivedData 必须放在项目目录之外，
这适用于 Debug 与 Release 两者。

## v0.5 自动测试证据（可重复）

```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates test
# 2026-09-18 实测：退出码 0；xcresult 实读 passedTests 188, failedTests 0, skippedTests 0
```

v0.5 新增/改写：`SettingsStoreTests`(5，新增)、`SourcePolicyTests`(改为排除语义)、
`TranslationCacheTests`(改为排除语义)、`TranslationCoordinatorTests`(+2：全局默认可读、无法归属仍拒绝)。

## F 组自动测试与构建证据（可重复，2026-09-18）

```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination platform=macOS -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test
# 2026-09-18 实测：退出码 0，TEST SUCCEEDED；xcresult 实读 passedTests 205 / failedTests 0 / skippedTests 0
#   单类可用 -only-testing:HoverTranslateTests/SelectionShortcutTests 等
xcodebuild ... -configuration Release ... build
# 2026-09-18 实测：退出码 0，本项目源码 0 warning；codesign --verify --deep --strict 通过；
#   产物 $HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app（0.5/5，3.6 MB）
```

本轮同时验证了 R3（日志）与 R4（快捷键注册）——把复制件直接运行并抓取实时日志：

```bash
log stream --style compact --level debug --predicate 'subsystem == "com.atat.HoverTranslate"'
# 实测：selection shortcut Control-Command-T status=0        （R4：系统接受注册，0 = noErr）
#       stage=accessibility gen=1 ms=0 outcome=success      （R3：阶段名 + 整数毫秒可读）
```

R4 的**冲突**路径本机无法实测：没有第二个应用注册同一组合；两份本应用实例各自注册同一组合都返回 0。
因此 `eventHotKeyExistsErr → .conflict` 只有单元测试证据，真机项见 F06（NOT RUN）。

## F 组手动验收步骤（2026-09-18 整改项，需要用户本人操作）

0. 先退出正在运行的实例，打开 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`
   （菜单栏只应有一个图标）。以下步骤都不会把任何原文发送到网络，除非你点了 Translate 或触发了悬停翻译。
1. **F01/F02**：在 TextEdit（或任意未被排除的应用）里选中一段英文 → 把鼠标移到另一个**已被排除**的应用窗口上 →
   按 Selection shortcut。期望：按**焦点所在应用**的策略执行，而不是按鼠标下的窗口；把焦点应用也加入排除列表后再按一次，
   期望只提示原因，且 `log stream` 里不出现 `stage=translation`。
2. **F02 密码框**：在任意密码输入框里选中字符（若可选中）后按快捷键，期望提示控件受保护、不读取、不发送。
3. **F03**：在应用 A 里选中英文并按快捷键，然后**立刻**切到应用 B（或立刻把 A 加入排除列表）。
   期望：迟到的选区不显示、不发送。
4. **F04**：先用 `pbcopy` 放一段文字，再从菜单打开 `Translate Selected or Pasted Text…`。
   期望：输入框是**空的**并提示粘贴；剪贴板内容没有自动出现。手动粘贴后**不点 Translate 不应有任何请求**。
5. **F05**：先悬停翻译一个词（不要关卡片），再到手动窗口翻译另一段并得到译文；分别点两个窗口的 Copy，
   确认各自复制的是各自的内容（可用 `pbpaste` 查看）。
6. **F06**：在你其它软件里占用 Control-Command-T（有全局快捷键设置的应用），重启 HoverTranslate →
   菜单栏应显示 "Control-Command-T is already used by another application. Pick another combination in Settings."，
   设置里同样提示；换一个组合后恢复正常。
7. **F07**：在设置里切换 Selection shortcut，期望新组合立刻可用、旧组合不再触发；退出应用后旧组合应能被其它应用使用。
8. **F09**：悬停一个词并在请求发出后立刻删 Key（或把来源加入排除列表，或在设置里关掉翻译开关），期望不显示旧译文；
   锁屏再解锁后，同一个词应重新请求（说明缓存已清空）。
9. **F10**：`log stream --predicate 'subsystem == "com.atat.HoverTranslate"' --level debug` 中应能看到
   `stage=accessibility gen=N ms=NN outcome=success|...`，并确认日志里没有原文、译文、Key、路径或窗口标题。

## E 组手动验收步骤（需要用户本人操作）

1. **E01**：设置里 Applications 列表应为空（显示 "No applications excluded"）。在一个**从未添加过**的应用
   （例如系统设置、Safari）里按住触发键悬停英文，期望直接出现卡片。
2. **E02**：用 `Exclude Application…` 把该应用加进去，再悬停同一个位置，期望**不再**取词（菜单 "Last query" 显示
   "this application is excluded in Settings"）；用 `Include Again` 去掉排除后恢复。
3. **E03**：无 bundle ID 的来源（某些辅助程序窗口）应失败而不是乱读。
4. **E04**：升级后第一次打开设置，确认当初勾选过的应用（TextEdit、Codex）**没有**出现在排除列表里，并且仍然可以取词。

## D 组手动验收步骤（需要用户本人操作）

1. 退出旧实例，打开 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`，确认菜单栏只有一个图标。
2. **D01**：在允许列表内的应用里悬停几次（含 Pin），打开 `Saved Entries…`，确认列表仍为空。
3. **D02/D03**：悬停一个词 → 松键 → `Save`；换一个语境再 Save 一次；`Quit HoverTranslate` 后重新打开 → 两条都还在；
   删掉其中一条，另一条不受影响。
4. **D04**：不点 `Explain` 时，用 `log stream --predicate 'subsystem == "com.atat.HoverTranslate"'` 确认不出现 `stage=explanation`。
5. **D05**：退出应用 → 把 `~/Library/Application Support/HoverTranslate/SavedEntries.json` 改成 `{ broken` → 重新打开：
   期望提示"文件无法读取"，且文件内容**没有**被改写；点 `Delete All…` 后才能恢复。
6. **D06**：`Clear cached translations` → 期望显示清除了几条；同一个词再悬停应重新请求（`stage=translation` 出现）。
   然后 `Remove key`，悬停与 `Explain` 都不应再联网。
7. **D08**：切换系统深色外观，并在一段很长的句子与图片英文上确认卡片不溢出、可读。

## C 组手动验收步骤（需要用户本人操作）

1. 退出当前在跑的实例，重新打开 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`，确认菜单栏只有一个图标。
2. **整句（C01/C02）**：在允许列表内的应用（TextEdit、浏览器）里输入两个句子，按住触发键 + Control 悬停在某句中的一个词上。期望：卡片只显示包含该词的那一句；句末没有标点或句子被窗口边缘截断时，caption 出现 `partial — select the full sentence to translate all of it`。
3. **不误截图（C03/C11）**：打开 OCR 开关但先不开屏幕录制，悬停 AX 能读的正文；同时运行
   `log stream --predicate 'subsystem == "com.atat.HoverTranslate"'`，确认不出现 `stage=ocr`。静置一分钟，确认 `stage=accessibility` 也不增长。
4. **真实 OCR（C04/C08）**：设置里打开 OCR → 点 **Request…** 并在系统设置中授权屏幕录制 → 重启应用 → 在一张**英文图片**上悬停。期望：卡片 caption 含 `ocr`；若浮窗正好覆盖在同一区域，重测一次确认识别结果不是浮窗自身的文字。
5. **拒绝即停止（C05）**：在系统设置里**关掉**屏幕录制权限后重复上一步，确认 `stage=ocr` 一次都不出现、应用不弹窗、不绕过。
6. **多屏（C09）**：若有外接屏，把窗口放在主屏左侧/上方的屏上复测词框与浮窗位置；没有设备就如实标"未测"。

## B 组真实 API 验证步骤（需要用户本人操作）

严格按 AGENTS.md：不批量打真实 API、不读取环境里的 Key，所以以下步骤只能由用户执行，代理只记录结果。

1. 允许列表里至少保留一个可读应用（例如 `com.apple.TextEdit`）。
2. 菜单栏 → Open Settings… → 在 DeepSeek API key 里粘贴自己的 Key → **Save key**。
3. 点击 **Test Connection**（只发送合成文本 `Open Settings`）。期望：显示 "Connection OK · model …"；失败时显示可操作错误。
4. 在 TextEdit 里输入 `charge`，按住触发键悬停：期望先出现原文，随后出现中文；断网时原文仍可读并提示网络错误。
5. 选中一段英文 → 按 **Control+Command+T**：期望弹出 Translate text 窗口并显示原文/译文；读不到选区时应提示并可从剪贴板粘贴。
6. 全部过程中不得出现：Key 出现在日志、半段译文被当成完成、自动查询改动剪贴板、超长文本被静默截断。
