# HoverTranslate 项目状态与续接

文档创建：2026-09-17。最后更新：2026-09-20（网页命中可靠性 + AX/OCR 统一跨行整句）。

> **关于本文中的提交哈希**：本文是公开发布前的开发账本，其中引用的 `c919289`、`08d94c5` 等哈希属于整理前的私有仓库历史。
> 公开仓库从单一初始提交开始，因此这些哈希在这里无法解析，仅作为当时的记录保留。

## 当前状态（唯一权威，2026-09-19 v0.7 结束时）

| 项目 | 当前事实 |
|---|---|
| 版本 | 0.7 / build 7（MARKETING_VERSION 0.7、CURRENT_PROJECT_VERSION 7，project.pbxproj 4 处全部更新）。**2026-09-20 的网页命中/跨行整句改动没有递增版本号**：它与 v0.7 在同一个未提交工作区里，是否递增等用户授权提交时再定 |
| 工程与分支 | `HoverTranslate.xcodeproj`；分支 `main`；HEAD = `c919289`（feat(v0.6): hover an existing selection，**未推送**）。Xcode 已打开本工程（MCP windowtab3 核对一致） |
| 工作区 | **有未提交的 v0.7 + 2026-09-20 改动**。v0.7：新增 `Dictionary/WordBook.swift`、`Dictionary/WordSenseProvider.swift`、`HoverTranslateTests/WordBookTests.swift`、`Resources/WordBook.tsv`、`Resources/WordBookLemmas.tsv`、`tools/build-wordbook.py`、`docs/THIRD_PARTY_NOTICES.md`；修改协调器、`AppDelegate`、`FloatingPanelController`、`TranslationCard`、两个测试文件、`ACCEPTANCE`、`USER_GUIDE`、设计文档、`project.pbxproj`（新增 Resources 构建阶段）。2026-09-20：新增 `Core/SentenceContextNormalizer.swift`；重写 `Core/SentenceResolver.swift`；改 `Core/OCRHitTester.swift`、`Extraction/AccessibilityTextExtractor.swift`、`Extraction/OCRTextExtractor.swift`、四个测试文件、`ACCEPTANCE`、`USER_GUIDE`、`RELEASE_NOTES`、设计文档、`project.pbxproj`（新增 1 个 Swift 文件）。**均未提交、未推送、未发布** |
| 自动测试 | **301 passed / 0 failed / 0 skipped**，`TEST SUCCEEDED`（2026-09-20 实测，xcresult 实读；本轮 +36＝句子规范化/边界 14 + OCR 几何与跨行 11 + AX 短控件与整句 11）。上一轮 v0.7 为 265，v0.6 为 252 |
| 构建与签名 | Debug/Release `xcodebuild` 退出码 0、本项目源码 0 warning；Release `codesign --verify --deep --strict` 通过；designated requirement 不含 cdhash（Apple Development: <开发者姓名>，team <团队ID>） |
| 日常运行路径 | `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`（0.7/7，含 2.6 MB 词库资源）；DerivedData 必须在项目目录之外 |
| 读取规则（当前唯一一套） | 悬停来源＝鼠标下最上层窗口的属主进程；选区来源＝**键盘焦点控件所属应用**；设置里是**排除列表**（默认空）；无 bundle ID 的来源与密码/安全控件一律拒绝。v0.6：触发键按住且指针稳定后，才向焦点控件询问"选区范围 + 选区屏幕矩形"，**只有指针确实落在选区内（且序号判定也落在选区内）才读选区正文**。v0.7：词库是**随包的本地文件**，只用已经读到的那个单词去查，不联网、不新增读取范围 |
| 整句修饰键 | 触发键 + **Control**（2026-09-18 由 Shift 改为 Control，用户要求）；`TriggerPolicy.mode(… control:)`、`TriggerController` 跟踪左右 Control（keyCode 59/62）；Shift 不再切换模式 |
| 整句边界（2026-09-20） | **单个排版换行不再截断句子**：先由 `SentenceContextNormalizer` 把同一段里的单个换行压成一个空格（空行仍是段落边界），再由 `SentenceResolver` 在规范化文本上用系统分句器找候选，并只在"左边界可证明（元素开头／前一句末标点／段落边界）且句末有有效终止符"时标 `complete`；否则 `partial`。AX 与 OCR **共用这一个解析器**。窗口仍是 2000 UTF-16 单元 |
| 网页短控件（2026-09-20） | 标签角色新增 `AXDisclosureTriangle`；候选顺序 `title` → `value` → `description` → **唯一直接文字子节点**（最多 8 个、只一层、同 PID、矩形相交、文字角色；两个候选就放弃）。短控件新增前置条件：**矩形有效且指针在矩形内**。OCR 整句改为先按几何拼局部行块（最多 6 行，双栏/表格/大间距断开）再交给同一个解析器 |
| 悬停命中坐标 | AppKit → AX **只转换一次**，命中控件与命中字符使用同一个点（2026-09-18 修复：此前命中直接用 AppKit 坐标，屏幕上下两端会命中别处） |
| OCR 限流 | 是"何时"而不是"不"：限流期间保留**一个**有界待办，到期重新核对触发键/代次/模式/来源/排除列表/权限后补试一次；无法满足即丢弃 |
| 悬停失败反馈 | 读不到时浮窗位置显示一行原因（约 1.4 s、非激活、点击穿透、同一句 1.5 s 内不重复）；等待识别时显示 `recognizing…` |
| 已验证层级 | 单元测试（可重复，含 AX 命中路径的假控件测试与红证据）、Debug/Release 构建、签名、Release 复制件启动、快捷键注册 `status=0` |
| 未验证层级 | 真实 DeepSeek API、真实整句范围、真实截图 OCR、多屏与排版、收藏/复制的真机 UI、**快捷键冲突的真实提示**（本机没有第二个应用占用预设）、选区入口的真实端到端 |
| 下一步 | 先按 `docs/ACCEPTANCE.md` 的 **J 组**（2026-09-20 网页命中与跨行整句：J01–J03 导航短控件、J05–J07 跨行整句与 partial、J08 双栏/表格、J04/J09 回归、J10 短控件不报矩形）在真机操作，再补 **I 组**（v0.7 词性释义）、G 组（v0.6 悬停选区）、H 组与 F/E/D/C/B/A 组；真实 API 验证只能由本人执行 |

> **本节是唯一权威。** 下面的"状态速览"与各"实施会话"是**历史记录**（写成当时的真实结果），
> 不再代表当前事实；出现"188/188 通过""ad-hoc 签名""允许列表"等表述时，以本节与源码为准。
> 历史摘要：v0.5 把来源策略由允许列表反转为排除列表；v0.4 主动收藏与按需解释；v0.3 悬停整句与 OCR 兜底；
> v0.2 DeepSeek 翻译、选区与手动入口；v0.1 触发键与 AX 取词。**需要用户手动执行的项仍为 NOT RUN**，
> 逐项状态见 `docs/ACCEPTANCE.md` 的 A–F 组与 2026-09-18 新增的 **H 组**（悬停可靠性修复）。

## 已知事实（历史记录：2026-09-17 当时实测；当前事实见顶部"当前状态"）

- 用户已确认 DeepSeek Harness 与 Xcode MCP 连接跑通。
- 本机：macOS 26.3（25D125）；Xcode 26.6（17F113）；SDK macosx26.5；部署目标设为 14.0（本机 SDK 可编译）。
- 项目真实路径：`/path/to/HoverTranslate_Execution_Pack`（含 `AGENTS.md`、`docs/`）。
  初始状态下该目录**不是** Git 仓库，父目录也不属于任何仓库，与 Light Balance 无关；已在此建立独立本地仓库。
- 代码签名：ad-hoc（`CODE_SIGN_IDENTITY = "-"`，Xcode 显示 "Sign to Run Locally"）。本机虽有 2 个 Apple Development 身份，但未替用户选择账号；因此**每次重新构建后 cdhash 变化，辅助功能授权需要重新授予**（见"未测与阻塞"）。
- 允许列表、开关等偏好写在 UserDefaults（`com.atat.HoverTranslate` 域），不含任何密钥。
- 本机同时存在多个 HoverTranslate 构建（项目内 `.build/DerivedData`、`~/Library/Developer/HoverTranslateDD`、Xcode 默认 DerivedData），**cdhash 各不相同**。
  实测坑：同时运行会造成菜单栏出现多个图标、辅助功能授权落在其中一份上而另一份始终未授权（菜单仍显示 Grant 按钮）。
  2026-09-17 起统一只用 Xcode 使用的路径：`$HOME/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp/Build/Products/Debug/HoverTranslate.app`。

## Xcode MCP 实际发现（未捏造）

- `XcodeListWindows` 实测返回两个窗口，均属于**另一个项目**：
  `windowtab1` / `windowtab2` → `.../LightBalance/LightBalance.xcodeproj`。
- 没有"创建工程"的 MCP 工具；`XcodeWrite`/`XcodeUpdate`/`XcodeBuild` 只能作用于上述 LightBalance 窗口。
  按 `AGENTS.md` 的项目边界，这些工具**本阶段一次都没有调用**。
- 因此：`.xcodeproj`、源码、构建与测试全部通过**当前项目目录的本地文件工具与终端**完成，未记为 MCP 操作。

## 环境坑（已定位并已处理）

项目目录位于 iCloud/FileProvider 管理的桌面文件夹，新建的构建产物会被写入 `com.apple.FinderInfo`，`codesign` 直接拒绝：
`resource fork, Finder information, or similar detritus not allowed`。

- 已加处理：两个 target 各有一个 `Strip filesystem detritus` run script（`xattr -cr`）。
- 该脚本能让 `.app` 通过签名，但 `.xctest` 内嵌进 `.app/Contents/PlugIns` 之后，`CopySwiftLibs` 在脚本之后运行并重新写入该属性，所以
  **`test` 必须把 DerivedData 放在项目目录之外**（本项目实测通过：`-derivedDataPath "$HOME/Library/Developer/HoverTranslateDD"`）。
- 项目内 `.build/` 只用于保存构建/测试日志。

## 当前执行状态（2026-09-17 v0.1 结束时）

| 项目 | 状态 |
|---|---|
| 当前阶段 | v0.1 已实现、已构建、单测通过；等待用户手动验收 |
| 项目真实路径 | `/path/to/HoverTranslate_Execution_Pack` |
| Git 分支 / 提交 | `main`（当时远程 `IndiumAndy/HoverTranslate`，private）；本次代码提交见文末"会话结束记录" |
| bundle ID / 签名 | `com.atat.HoverTranslate`；ad-hoc 本地签名；`LSUIElement = true`（仅菜单栏） |
| 构建 | **PASS**：`xcodebuild ... build` 退出码 0；`codesign --verify` 通过 |
| 自动测试 | **PASS**：49 个用例全部通过（8 个测试类），退出码 0 |
| 真实应用取词（AX） | **未执行**：需要用户在系统设置里授予辅助功能权限后才能实测 |
| 浮窗真实显示/点击穿透 | **未执行**（同上，属于 GUI 人工验收） |
| API Key | 未涉及；v0.1 无网络层 |
| 屏幕捕获权限 | 未申请（v0.1 不需要） |

## 实测命令与结果

```bash
# 红：只有测试文件、没有实现时（真实红灯）
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  -only-testing:HoverTranslateTests/TriggerPolicyTests test
# 退出码 65；8 个测试文件全部报 "cannot find type ... in scope"

# 绿：实现完成后（DerivedData 必须在项目目录之外，原因见上）
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  build     # 退出码 0
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  test      # 退出码 0，49 passed / 0 failed
```

产物：测试用 `$HOME/Library/Developer/HoverTranslateDD/...`；**运行用** `$HOME/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp/Build/Products/Debug/HoverTranslate.app`

## 本阶段已实现（v0.1）

- 菜单栏应用（`MenuBarExtra` + `LSUIElement`）：Enable 开关、触发键左右选择、允许列表、辅助功能授权引导、状态行、退出。
- 应用允许列表默认空：未加入的应用一律不读取（`SourcePolicy`，`SourcePolicyTests`）。
- 触发：右/左 Option 分别按 keyCode 跟踪（58/61），不使用聚合 option 标志；不读取 `event.characters`；不吞事件。
- 稳定判定：250 ms + 4 点锚点半径，锚点会随超限移动重置（`HoverDwell`）。
- 取词来源：**鼠标下最上层窗口的属主进程**（`CGWindowListCopyWindowInfo`，只读属主 pid 与窗口矩形，不读窗口内容，不需要屏幕录制权限；纯选择逻辑 `PointerWindowPicker`，3 个测试）。**不是**前台 app——前台 app 只在鼠标下的窗口恰好是前台窗口时才一致。
- 精确取词：`AXUIElementCopyElementAtPosition` → PID/来源核对 → 敏感控件拦截 → `AXRangeForPosition` → 有界 `AXStringForRange` → UTF-16 偏移解析单词 → 用 `AXBoundsForRange` 取词框；只有覆盖鼠标的精确单词才标 `word`，短控件标签标 `label`，否则明确失败。
- AX 调用在专用串行队列，只返回值快照；消息超时 0.3 s。
- 浮窗：非激活 NSPanel，按住时鼠标穿透且无按钮；松键冻结 1 s、显示 Pin/Close、进入浮窗暂停关闭、移出 600 ms 关闭；Pin 后不被新悬停覆盖。
- 请求失效：递增 generation（`RequestGate`）+ 任务取消 + 显示前再次校验；松键/切应用/锁屏/显示器变化/点击/滚动/普通按键都会使结果失效。
- 单测 49 项覆盖：触发策略、稳定判定、单词解析、坐标与卡片摆放、允许列表、代次失效、卡片生命周期、协调器乱序/迟到/失败/固定流程。

## 2026-09-17 修复会话（v0.1 验收期间，实机定位）

现象与实测证据：

- 用户已按系统提示授予辅助功能权限，但真机按住触发键后**始终没有浮窗**；菜单 "Last query" 显示 `the pointed window belongs to another application`。
- 期间还出现"已授权但菜单仍有 Grant Accessibility Access… 按钮"，实测原因是**同时存在两个实例**：用户授权的是 Xcode 那份构建，看到的是另一份未授权实例的菜单。
- tccd 日志（`process == "tccd"` 实时流）实测：`2026-09-17 02:36:59` 弹出授权提示（universalAccessAuthWarn），`02:37:02` 记录 `type=Modify, service=kTCCServiceAccessibility, identifier=com.atat.HoverTranslate`；应用自身日志 `02:37:14 extraction started` → `extraction failed`。证明**权限与按键监视均正常，失败发生在取词来源核对**。
- 关键反证：该实例 PID 20501 于 `02:36:56` 启动、`02:37:02` 授权、中间未重启，`02:37:14` 就收到了 Option 事件 —— 说明全局按键监视器**授权后会自动开始工作，不需要重启**（`NSEvent.addGlobalMonitorForEvents` 在未授权时也返回非 nil，实测 `trusted=false monitor=non-nil`）。

根因（两条，均已修复）：

1. 取词来源用 `NSWorkspace.frontmostApplication`（前台 app）。鼠标只是移到某个非前台窗口上（很常见）时，前台仍是别的 app，于是鼠标下元素的 pid 与来源 pid 不符 → `sourceMismatch`。
2. 允许列表拒绝被报成 `.notPermitted`，文案是 "accessibility permission is required"，把用户引向反复排查系统权限（已改为 `.sourceNotAllowed` / "this application is not in the allowed list"）。

改动（本次提交）：

- `TranslationCoordinator.swift`：`SourceLocating.currentSource(at:)` 改为按鼠标位置取来源；新增 `PointerWindowSourceLocator`、`PointerWindowPicker`、`WindowList`；加入来源 pid/bundle 的 debug 日志（不含任何原文）。
- `AccessibilityTextExtractor.swift`：失败路径记录命中元素的 pid/role（只记 pid 与 role，不记文本），便于下次直接看日志定位。
- `ExtractionSnapshot.swift`：新增 `ExtractionFailure.sourceNotAllowed` 与文案。
- `TriggerController.swift`：`keyMonitorAvailable` 改为实时计算（`keyMonitor != nil && AXIsProcessTrusted()`），监视器仍无条件安装以保留"授权后自愈"。
- 测试：新增 `PointerWindowPickerTests` 3 项、`TriggerPolicyTests` 2 项，更新 `TranslationCoordinatorTests` 的允许列表断言。

手动验收（用户确认）：修复后在真机悬停**浮窗出现**（`present()` 会调用 `orderFrontRegardless()`，因此浮窗可见即取词成功）。用户设置实测：触发键为 **Left Option**（`HoverTranslate.useRightOption = 0`），允许列表为 `com.apple.TextEdit`、`com.openai.codex`（**不含 Chrome**）。

## 2026-09-17 真机交互补充（用户口述确认）

- 松键后 Pin / Close 按钮出现，**点击有效** → A09 真机部分通过。
- 快速从词 A 移到词 B，卡片**正确切换为 B** → 真机通过（乱序迟到结果仍只有单测证据）。
- 触发键为 Left Option 时真机可用 → 左右 Option 设置至少"左键模式"已实测。
- **待确认**：用户报告滚动/切换应用时卡片**不消失**。因为同一轮刚验证过 Pin，无法区分当时卡片是否处于 Pin 状态；按设计 Pin 卡片本来就不消失（`cancelOutstanding` 对 pinned 直接返回）。需在**未 Pin** 状态下重测后才能判定 A07 是否失败。

（2026-09-18 更正：A07 已在 `docs/ACCEPTANCE.md` 记录为**用户真机确认通过**（"A07 没有问题"）；上面这段"待确认"是 2026-09-17 当时的记录，不是当前结论。）

## 签名与发布（2026-09-17 变更）

- 用户选定 **Apple Development: <开发者姓名> (<证书ID>)**（team `<团队ID>`）。两个 target 的 Debug/Release 均改为 `CODE_SIGN_IDENTITY = "Apple Development"` + `DEVELOPMENT_TEAM`，`CODE_SIGN_STYLE = Automatic`。
- 实测 designated requirement 已不含 cdhash：`identifier "com.atat.HoverTranslate" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: <开发者姓名> (<证书ID>)" and certificate 1[...]` → **重新构建不再需要重新授权**（切换身份这一次仍需重新授权一次）。
- 构建命令加 `-allowProvisioningUpdates`（首次让 Xcode 处理签名）。
- 远程仓库（当时）：GitHub `IndiumAndy/HoverTranslate`（private，默认分支 `main`），实测已推送 `main` = 9a0ea09、tag `v0.1`。
- 公开仓库（2026-09-20 整理）：`IndiumAndy/LightTranslate`（**public**），从单一初始提交开始，只含整理后的 HEAD 内容。
- **每个版本结束的固定做法**：更新 `docs/PROJECT_STATUS.md` 与 `docs/ACCEPTANCE.md` → 提交 → `git tag -a vX.Y -m "..."` → `git push --follow-tags`。

## v0.2 翻译方案调研（2026-09-17，**仅调研，未实现**）

用户提出 DeepSeek API 费用顾虑，问是否有本地方案。本机实测/官方文档核对结果：

1. **系统词典可用且直接给中文**——实测编译运行 `DCSCopyTextDefinition`（CoreServices 的 DictionaryServices，macOS 14 target 可编译）：
   `charge` 返回 3366 字符，形如 `charge | BrE tʃɑːdʒ, AmE tʃɑrdʒ | A. transitive verb ① (ask for as payment) 收取 shōuqǔ …`；`battery` 返回 `… 电池 diànchí …`。
   **零成本、离线、即时、权威（系统英汉词典）**，缺点：只覆盖词典词条（屈折形式/短语可能查不到）、返回带格式需截断解析、依赖用户已启用中文词典。
2. **Apple Translation 框架本机可用，但部署目标需门控**——用本机 SDK 实测：`TranslationSession` `-target arm64-apple-macos14.0` 报错 "only available in macOS 15.0 or newer"，`macos26.0` 通过。文档（`TranslationSession.Strategy.lowLatency`）：使用前需下载语言，下载后**对设备上所有 App 可用**，用 `prepareTranslation()` 预先下载。离线、零成本，适合单词**和整句**（v0.3 也需要）。代价：语言包下载流程 + `@available(macOS 15, *)` 门控。
3. **DeepSeek 费用实测不构成负担**（定价来源：`https://api-docs.deepseek.com/quick_start/pricing`，经第三方镜像读取的 2026-08-23 快照，**实现时必须再核对官方页面**）：
   `deepseek-v4-flash` 输入（缓存未命中）$0.22/M off-peak、$0.44 峰值；输出 $0.66/M、$1.32 峰值；缓存命中输入 $0.007/$0.014。峰值时段为 UTC 周一至周五 01:00–04:00、06:00–10:00，其余为 off-peak（半价）。
   按本应用一次单词查询约 200 输入 + 60 输出 token 估算：**≈ $0.00008/次 ≈ 0.0006 元**；1 万次约 $0.8（≈6 元），每天 100 次用一年约 $3（≈21 元）。pro 档约 3 倍。

候选方案对比（待用户决定，未开始实现）：

| 方案 | 成本 | 离线 | 适用 | 代价 |
|---|---|---|---|---|
| A 系统词典 DictionaryServices | 0 | 是 | 单词释义（含拼音、义项） | 仅词条；需解析/截断；依赖已启用中文词典 |
| B Apple Translation 框架 | 0 | 是（首次下载语言包后） | 单词 + 整句 | 语言包流程；需 macOS 15+ 门控 |
| C 本地小模型（如 Ollama） | 0（电费） | 是 | 可做上下文解释 | 数 GB 模型、内存、额外服务 |
| D DeepSeek API（原计划） | ~6 元/万次 | 否 | 上下文解释最强 | Key、网络、隐私、代码量 |

建议（待用户确认）：v0.2 单词模式以 **A 为主**，配合 **B** 处理屈折形式/整句；保留计划中的 `TranslationService` 抽象，把 D 留给 v0.4 的"解释/上下文"场景。若采纳，v0.2 计划的任务 1–2（HTTP 适配、错误映射、Keychain、Test Connection）大部分不再需要，需改写 `docs/superpowers/plans/2026-09-17-v0.2-translation.md`。

## v0.2 实施会话（2026-09-17）

**范围**：执行 `docs/superpowers/plans/2026-09-17-v0.2-translation.md` 的三个任务（翻译服务与错误映射、Keychain/缓存/协调器、选区与手动粘贴入口）。
用户提到的 `v0.2-foundation.md` 在包内不存在；v0.2 计划文件名为 `2026-09-17-v0.2-translation.md`。

**方案核对（实测，非推测）**：
- 2026-09-17 抓取官方 `https://api-docs.deepseek.com/api/create-chat-completion`（本机 DNS 被代理映射到 198.18.x，web_fetch 拒绝，改用 `curl -sSL` 直接读取）：
  `model` 取值为 **`deepseek-flash` / `deepseek-v4-pro`**；`thinking` 是对象且 **默认 `enabled`**，因此翻译请求必须显式发 `{"type":"disabled"}`；
  `max_tokens` 取值 1–384K；`stream` 默认 false；`finish_reason` ∈ {stop, length, content_filter, tool_calls, insufficient_system_resource, aborted}。
- 因此 v0.2 按设计文档第 7 节实现 DeepSeek 适配器（`TranslationService` 抽象保留，后续可换本地引擎），
  **未实现**上一节调研列出的本地方案 A（DictionaryServices）/B（Apple Translation）——它们不在 v0.2 计划内，且 B 需要 macOS 15 门控。

**已实现**：
- `TranslationFailure`：`apiKeyMissing/invalidKey/insufficientBalance/rateLimited/network/timeout/invalidResponse/truncatedOutput/cancelled/configuration`，每条都有可操作文案。
- `TranslationRequestBuilder`：JSON 序列化构造请求体（不是字符串拼接），固定系统提示词、`thinking.disabled`、`stream:false`、按模式的上限（word 160 / sentence 800 / selection 2400 / explanation 900）、`temperature 0.2`；
  原文只出现在 user 消息里，且作为 JSON 值编码，注入文本无法改变请求结构。
- `DeepSeekTranslationService` + `HTTPPerforming` 注入点：15 秒超时、ephemeral URLSession、`RedirectRefusingSessionDelegate` 拒绝一切重定向（Key 不会被转发到其它主机）、不自动重试；
  只有 `finish_reason == "stop"` 且 content 非空才算成功；`length` → `truncatedOutput`；未知/中断原因 → `invalidResponse`；失败从不携带原始响应体。
  **402 不映射成"余额不足"**（客户端无法得知真实原因），归入 `invalidResponse`；`insufficientBalance` 枚举保留备用。
- `KeychainStore`（service `com.atat.HoverTranslate`，account `deepseek-api-key`）：写入/替换/删除，只操作本应用条目；Key 不进 UserDefaults、不进源码、不进日志。
- `CacheKey` + `TranslationCache`（actor）：容量 256、TTL 600 秒、可注入时钟；键含 mode/text/context/目标语言/provider/model/promptVersion；
  读取前先做来源允许列表检查；允许列表变化或删除 Key 时清空对应条目。
- 协调器接入：翻译沿用同一条 generation；松键/移动/切应用会使翻译失效；缓存命中不发请求；无 Key 时不发请求并在卡片上说明；
  失败时保留本地原文；同一时间只保留一个翻译任务。
- 卡片：原文 + 译文 + 状态 + **Copy / Pin / Close**；Copy 只在用户点击时写剪贴板（自动查询不碰剪贴板）。
- 手动入口：独立窗口 `ManualTranslationView`（不是浮窗状态），显示将发送的原文、4000 字符上限计数、Translate 按钮；
  读不到选区时用剪贴板预填（明确告知"已从剪贴板预填，按 Translate 发送"），用户可改。
- 选区快捷键：`SelectionShortcutController` 用公开 NSEvent 监视注册 **Control+Command+T**（与菜单项同快捷键），不吞事件；
  通过 AX 读取当前焦点元素的 `kAXSelectedText`，安全文本域直接拒绝，绝不模拟 Command+C。
- `TextInputPolicy`：按 Unicode 字符计数、上限 4000，空白拒绝，超限**明确拒绝不静默截断**。

**实测命令与结果**：
```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates build      # 退出码 0，0 warning
xcodebuild ... test                    # 退出码 0，TEST SUCCEEDED
# xcresult 汇总：total 102, passed 102, failed 0, skipped 0
```
测试类分布（本次实测）：TranslationCoordinatorTests 17、TranslationServiceTests 16、TranslationCacheTests 9、TextResolverTests 9、
HoverDwellTests 7、TriggerPolicyTests 7、TranslationRequestBuilderTests 6、CoordinateMapperTests 6、CardLifecycleTests 5、
KeychainStoreTests 5（真实 Keychain，test-only service 名，用完即删）、RequestGateTests 4、SourcePolicyTests 4、TextInputPolicyTests 4、
PointerWindowPickerTests 3。
签名：designated requirement **不含 cdhash**（Apple Development: <开发者姓名> <证书ID>），因此本次重建**不需要**重新授权辅助功能。

**构建产物（本次）**：`$HOME/Library/Developer/HoverTranslateDD/Build/Products/Debug/HoverTranslate.app`（先用它做自动测试与启动验证）。
**用户运行用的稳定路径已同步为 v0.2**：`$HOME/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp/Build/Products/Debug/HoverTranslate.app`
（本次实测：`xcodebuild build` 退出码 0、`codesign --verify --deep --strict` 通过、designated requirement 不含 cdhash，因此旧的辅助功能授权继续有效）。
另一份新构建在 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Debug/HoverTranslate.app`（自动测试与启动验证用）。
**运行前请先确认没有第二份实例在跑**（`pgrep -fl HoverTranslate`），否则会出现两个菜单栏图标与"授权落在另一份上"的假象。
**实测坑（本次踩到）**：把 `-derivedDataPath` 指到项目内目录会在最后 CodeSign 阶段失败
（`resource fork, Finder information, or similar detritus not allowed`）——iCloud/FileProvider 在 Strip 脚本之后又写回属性。
继续遵守既有结论：DerivedData 必须放在项目目录之外。

**本次期间发现的实现缺陷（已修）**：松键只释放卡片、没有让 generation 失效，导致迟到的译文仍可能显示；现改为松键时
`discardOutstandingWork()`（失效 generation + 取消任务，但保留已显示内容）。自动测试 `testReleasingTheTriggerDropsALateTranslation` 覆盖。

**真实 API 验证（未执行）**：按 AGENTS.md 不进行付费真实 API 批量测试，也不读取用户环境里的 Key。
用户需要在设置里自行输入 Key → 点击 **Test Connection**（只发合成文本 `Open Settings`）→ 再在允许列表内的应用上实测悬停翻译。

**启动验证（本次）**：新构建的 .app 实际启动并保持运行约 15 秒无崩溃、无崩溃报告，随后被主动结束以免出现两份菜单栏图标。
GUI 交互（真实悬停翻译、快捷键、手动窗口、剪贴板不变）仍需用户手动执行，见 `docs/ACCEPTANCE.md` B 组。

## v0.3 实施会话（2026-09-17）

**范围**：执行 \`docs/superpowers/plans/2026-09-17-v0.3-sentence-ocr.md\` 的三个任务（悬停整句；OCR 兜底策略、单帧与词框定位；兼容性与性能收口）。

**方案核对（实测，非推测）**：
- 本机 macOS 26.3（25D125）、Xcode 26.6、SDK macosx26.5。用 \`xcrun -sdk macosx swiftc -target arm64-apple-macos14.0 -typecheck\` 实测：\`SCShareableContent.excludingDesktopWindows\`、\`SCContentFilter(desktopIndependentWindow:)\`、\`SCScreenshotManager.captureImage(contentFilter:configuration:)\`、\`VNRecognizeTextRequest\`、\`VNRecognizedText.boundingBox(for:)\` 在部署目标 14.0 下全部可编译；\`SCStreamConfiguration.includeChildWindows\` 需要 14.2，因此**未使用**；SDK 里另有 **macOS 26.0 才有的 \`SCScreenshotConfiguration\`**，也未使用，项目继续走 14.0 可用的 \`SCStreamConfiguration\` 路径。
- **唯一无法在本机实测的假设**：SDK 头文件 \`SCStream.h\` 原文是 "The rectangle is specified in points in the display's logical coordinate system"，对独立窗口流并没有说清是窗口坐标还是显示器坐标。本实现按**窗口局部坐标**传入（\`CoordinateMapper.windowLocalRect\`），修正点集中在 \`ScreenCaptureService.captureFrame\` 一处。若该假设不成立，表现是**OCR 一直找不到词**（不会给出错误区域的译文），因为词框会整体偏移、命中测试拿不到结果——即"失败安全"，而不是"读错内容"。
- \`NLTokenizer(unit: .sentence)\` 实测行为：\`Dr.\` / \`e.g.\` / \`3.14\` 不误断句；**硬换行是句子边界**（跨行不会被拼成一句）。所以"跨行不拼接"由系统分句器天然满足，"同一句在窗口边缘被裁"由 \`SentenceResolver.isComplete\` 标 partial。
- 未装 superpowers 等技能，按计划文件逐项执行，未安装任何插件。

**已实现**：
- **句子模式**：\`TriggerPolicy\` 在 Option+Shift 时返回 \`.sentence\`；\`TriggerController\` 通过 \`.flagsChanged\` 的 modifier flags 跟踪左右 Shift（不读 \`event.characters\`、不吞事件）；\`TranslationCoordinator\` 把手势模式固定，**中途按下或松开 Shift 会失效旧 generation、重新计时**（\`testSwitchingToSentenceModeDropsTheWordRequest\` / \`testReleasingShiftDropsTheSentenceRequestAndReturnsToWord\`）。
- **\`SentenceResolver\`**：NaturalLanguage 分句 + 2000 UTF-16 单位有界窗口；\`isComplete\` 只在"窗口两端都没有被裁"且"结尾是句末标点（允许尾随引号/括号）"时才标 complete，否则 partial。列表项、无标点的硬换行行都是 partial。
- **\`AccessibilityTextExtractor\`**：把"位置→字符范围"探测拆成 \`positionMapping\`（\`resolved/unsupported/none\`），句子模式下**短标签角色（按钮/菜单项/复选框…）不走分句路径**，直接按 label 处理，避免把相邻菜单项拼成一句；新增 \`.notSupported\` 用来区分"控件不具备位置映射"和"此处没有词"。词模式行为保持不变（同样一次 AX 调用，同样的覆盖校验）。
- **卡片/菜单文案**：caption 现在显示 scope、来源、句子字符数；partial 时显示 "partial — select the full sentence to translate all of it"。菜单与设置里说明 Shift 的用法。
- **OCR 兜底**：\`OCRFallbackPolicy\`（只允许 \`.noText\`/\`.notSupported\`/\`.positionUnresolved\`，且 userEnabled + captureAuthorized + sourceConfirmed 三者同时满足；敏感控件、权限拒绝、来源不允许、未知来源、超时**永不**触发截图）；\`OCRRateLimiter\`（800 ms、至多一个）；\`OCRHitTester\`（真实命中 ±2 pt、置信度 ≥0.65、空白处没有结果；\`lineRun\` 在双栏间隙处断开，禁止串栏）；\`ScreenCaptureService\`（ScreenCaptureKit **单帧**、窗口过滤器、前置 \`CGPreflightScreenCaptureAccess()\`、不启动录屏也不采集音频、返回像素尺寸与请求不符就丢弃而不是猜）；\`VisionTextRecognizer\`（本机 Vision、逐词真实词框、不按等宽均分字符）；\`OCRTextExtractor\`（识别在专用串行队列执行，绝不在主线程同步识别；OCR 句子模式一律标 partial，因为单帧无法证明跨行/跨栏）。
- **来源窗口身份贯通**：\`WindowList\` 现在额外读取 \`kCGWindowNumber\`（仍不需要屏幕录制权限——只读属主与几何，不读内容），\`SourceApp\`/\`ExtractionRequest\` 携带该窗口 ID；OCR 只捕获**已经确认的那一个窗口**，没有窗口 ID 时直接失败（不重新猜窗口）。
- **设置与权限**：\`SettingsStore.isOCRFallbackEnabled\` 默认 **false**；只有用户打开开关且尚未授权时才调用 \`CGRequestScreenCaptureAccess()\`（必须由用户显式操作触发）；协调器只用 \`CGPreflightScreenCaptureAccess()\` 检查，因此拒绝授权不会反复弹窗。
- **度量（任务 3）**：每个请求按阶段记录 \`stage/gen/ms/outcome\`（只有阶段名、generation、毫秒数和结果类别，**不含原文、译文、图片、窗口标题或路径**）；新增计数 \`ocrStarts\`、\`cacheHits\`（连同既有 \`extractionStarts\`、\`translationStarts\`）用于核对"静置未触发时读屏/截图/联网计数不增长"。

**重命名（对齐 v0.3 计划的接口）**：\`ExtractionFailure\` 的 \`notPermitted→permissionDenied\`、\`sourceNotAllowed→appNotAllowed\`、\`sourceMismatch→unknownOwner\`、\`timedOut→timeout\`，并新增 \`notSupported\`；\`ExtractionFailure\` 与 \`TranslationFailure\` 改为 \`String\` 原始值（原始值即日志类别名）。**用户可见文案未变**（例如仍是 "this application is not in the allowed list"），\`docs/ACCEPTANCE.md\` 的 B 组引用不受影响。
计划里列出的 \`stale\` **没有添加**：没有任何代码路径会产生它——迟到结果由 generation 门直接丢弃，而不是变成一个失败状态；加进去就是死代码。

**实测命令与结果**：
\`\`\`bash
cd "/path/to/HoverTranslate_Execution_Pack"
# 红：先写测试、实现不存在时（真实红灯）
xcodebuild ... -only-testing:HoverTranslateTests/SentenceResolverTests test
# 退出码 65；error: cannot find 'SentenceResolver' in scope（12 处）
xcodebuild ... -only-testing:HoverTranslateTests/OCRFallbackPolicyTests \
  -only-testing:HoverTranslateTests/OCRHitTesterTests -only-testing:HoverTranslateTests/CoordinateMapperTests test
# 退出码 65；error: cannot find 'OCRFallbackPolicy' / 'OCRRateLimiter' in scope

# 绿：实现完成后（DerivedData 继续放在项目目录之外）
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates build     # 退出码 0，0 warning（本项目源码）
xcodebuild ... test                   # 退出码 0，TEST SUCCEEDED
# xcresult 汇总（实读）：passedTests 155, failedTests 0, skippedTests 0, expectedFailures 0
\`\`\`
测试类分布（本次实测）：TranslationCoordinatorTests 26、CoordinateMapperTests 17、TranslationServiceTests 16、
SentenceResolverTests 12、TriggerPolicyTests 9、TranslationCacheTests 9、TextResolverTests 9、OCRImageTests 7、
OCRHitTesterTests 7、HoverDwellTests 7、TranslationRequestBuilderTests 6、OCRFallbackPolicyTests 5、KeychainStoreTests 5、
CardLifecycleTests 5、TextInputPolicyTests 4、SourcePolicyTests 4、RequestGateTests 4、PointerWindowPickerTests 3。
v0.3 新增测试类：\`SentenceResolverTests\`、\`OCRFallbackPolicyTests\`、\`OCRHitTesterTests\`、\`OCRImageTests\`；
\`CoordinateMapperTests\`（+11）、\`TranslationCoordinatorTests\`（+9）、\`TriggerPolicyTests\`（+2）扩充。

**用户运行路径（本次已重建）**：\`$HOME/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp/Build/Products/Debug/HoverTranslate.app\`
- \`xcodebuild build\`（不带 \`-derivedDataPath\`，即 Xcode 默认 DerivedData 位置）退出码 0；\`codesign --verify --deep --strict\` 通过。
- designated requirement 实测仍为 \`identifier "com.atat.HoverTranslate" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: <开发者姓名> (<证书ID>)" and certificate 1[field.1.2.840.113635.100.6.2.1]\` —— **不含 cdhash**，因此本次重建不需要重新授予辅助功能权限。
- **启动验证（本次执行）**：把新构建复制到 \`/tmp/HTVerify/\`（复制件 \`codesign --verify --deep --strict\` 通过）后启动，持续运行 12 秒无退出、无输出、\`DiagnosticReports\` 无新崩溃报告，随后主动结束该副本。
  **没有**结束已经在跑的那一份（PID 28324，启动于 03:40），以避免同时出现两个菜单栏图标；那一个是 v0.2 代码，磁盘上的 bundle 已经是 v0.3，**用户退出并重新打开即运行 v0.3**。

**失败安全（设计上刻意如此）**：OCR 只有在 AX 报技术性失败时才会启动；一旦启动，若窗口、区域、像素尺寸或词框命中任一环节无法确定，就返回失败并在卡片上说明，不会给出"就近的词"或错误区域的译文。

## v0.4 实施会话（2026-09-17）

**范围**：执行 `docs/superpowers/plans/2026-09-17-v0.4-learning-release.md` 的两个任务（主动收藏与按需解释；设置收尾、回归与本机可运行应用）。
用户在本次会话里明确授权直接开始 v0.4；v0.3 的 C 组手动验收仍未由用户执行，因此继续保留为未测（见"未测与阻塞"）。

**计划文件映射**：v0.4 计划里写的 `HoverTranslate/Settings/TranslationSettingsView.swift` 在本工程不存在，
实际的设置界面是 `HoverTranslate/Settings/SettingsView.swift`（v0.2 起沿用）。按主计划"已有工程命名不同则先记录映射"处理，未新建第二份设置视图。

**已实现**
- **收藏**：`SavedEntry(source:translation:context:)`（自动 id/createdAt）与 `LearningStore(directory:)` 的
  `save/all/remove(id:)/removeAll`，JSON 原子写入，首次保存才创建目录。应用写 Application Support；
  测试一律用独立临时目录。损坏文件**不会被覆盖**：`all()`/`save()` 都抛 `.unreadable`，文件保持原样，
  只有用户点 Delete All 才重写。
- **解释**：`ExplanationRequestBuilder` 复用同一请求构造（`TranslationRequestBuilder.makeBody` 新增 `systemPrompt` 参数），
  模式 `.explanation`、输出上限 900 tokens、`thinking.disabled`、`stream:false`；提示词只要当前语境含义与一句用法说明，
  明确不生成词源/音标/例句列表。卡片上标明 `AI explanation · not a dictionary entry`。
- **协调器**：`explainDisplayedText()`（只允许在 frozen/pinned 阶段；点击后才 begin 新 generation，走同一缓存、
  同一 Keychain 与同一失败映射）、`saveDisplayedText()`（只在点击时写；没有译文就拒绝并提示；写失败在卡片上说明而不是吞掉）、
  `clearTranslationCache()`（await 真实清空并返回条数）。新增计数 `explanationStarts`、`cacheHits`，
  以及 `didSaveEntry` 回调让已打开的收藏窗口刷新。三个请求路径共用同一个 `cachedAnswer` 缓存查入口。
- **界面**：卡片新增 Save / Explain 按钮与解释区；新增 `LearningView` + `LearningModel`（列表、单条删除、
  全部删除带确认、损坏文件提示、⌘W 关闭）；菜单新增 `Saved Entries…`；设置新增 Saved entries 区块与
  `Clear cached translations`，并把选区快捷键做成可选预设（默认 Control-Command-T）。
- **隐私边界**：收藏只保存用户主动保存的原文/译文/短语境；不保存窗口标题、路径、截图或应用名。

**本次实测发现的缺陷（已修，并有测试）**
1. **模型设置此前不起作用**：`DeepSeekTranslationService.translate` 请求体里硬编码 `model: "deepseek-flash"`，
   设置里的模型只进了缓存键。现在由配置层把模型作为参数传入；空模型在发请求前抛 `.configuration`。
   测试：`testTheConfiguredModelIsWhatTheRequestAsksFor`、`testAnEmptyModelIsRefusedBeforeAnyRequest`。
2. **收藏日期精度**：ISO-8601 丢亚秒 → 写盘再读回的对象与原对象不相等。改用 Foundation 全精度日期编码；
   测试：`LearningStoreTests.testEntriesAndTheirIdentitySurviveARestart`。
3. **写死的菜单快捷键**：菜单项 `Translate Selected or Pasted Text…` 曾固定绑定 Control-Command-T，
   与可配置的全局快捷键既误导又有重复触发的风险；已移除该 key equivalent（真正的快捷键由全局监视器负责）。

**实测命令与结果**
```bash
# 红：先写测试、实现不存在时（真实红灯，退出码 65；cannot find 'LearningStore' / 'ExplanationRequestBuilder' in scope）
# 绿：
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates test
# 退出码 0；xcresult 实读：passedTests 182, failedTests 0, skippedTests 0
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Release -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" -allowProvisioningUpdates build
# 退出码 0；本项目源码 0 warning
```
测试类分布（本次实测）：TranslationCoordinatorTests 34、TranslationServiceTests 18、CoordinateMapperTests 17、
SentenceResolverTests 12、TriggerPolicyTests 9、TranslationCacheTests 9、TextResolverTests 9、OCRImageTests 7、
OCRHitTesterTests 7、LearningStoreTests 7、HoverDwellTests 7、TranslationRequestBuilderTests 6、SelectionShortcutTests 5、
OCRFallbackPolicyTests 5、KeychainStoreTests 5、CardLifecycleTests 5、TextInputPolicyTests 4、SourcePolicyTests 4、
RequestGateTests 4、ExplanationRequestBuilderTests 4、PointerWindowPickerTests 3。
v0.4 新增测试类：`LearningStoreTests`、`ExplanationRequestBuilderTests`、`SelectionShortcutTests`。

**Release 构建与路径（实测存在，不是推断）**
- 产物：`$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`
  （CFBundleShortVersionString **0.4**、CFBundleVersion **4**、3.4 MB）；`codesign --verify --deep --strict` 通过；
  designated requirement 仍不含 cdhash（重建不需要重新授权辅助功能）。
- 版本号由 0.1 提升到 0.4（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION = 4`）。
- **计划里的 Release 命令在本机不可用**：`-derivedDataPath .build/DerivedData`（项目目录内）实测"构建成功但产物签名无效"——
  iCloud/FileProvider 在签名后写回 FinderInfo，`codesign --verify` 报 `resource fork, Finder information, or similar detritus not allowed`。
  Debug 与 Release 都改用项目目录之外的 DerivedData；偏差写进 `docs/RELEASE_NOTES.md` 与 `docs/USER_GUIDE.md`。
- 启动实测：Release 产物复制到 `/tmp` 后启动，12 秒无退出、无输出、无新崩溃报告，随后主动结束（未干扰正在运行的实例）。

**文档**：新增 `docs/USER_GUIDE.md`（打开方式、两个权限、操作表、撤销与清理、已知限制）与
`docs/RELEASE_NOTES.md`（新增/修复/构建/测试/未测）。

**未实测（需要用户手动）**：真实整句取词、屏幕录制授权后的真实截图 OCR、多屏摆放、真实 DeepSeek API 翻译、
剪贴板不变、深浅色与较大字号排版、Saved entries 窗口的键盘操作，以及收藏在真机 UI 上的保存→重启→查看往返
（自动测试覆盖了存储层，但没有真机 UI 操作证据）。

## v0.5 实施会话（2026-09-18）用户要求的"全局可用"

**范围**：用户在本会话明确要求"任何应用都能取词，不再逐个添加允许列表"（并确认了这条解释）。
这不在四阶段计划内，是对已完成 v0.4 的后置行为变更。

**变更**：来源策略由**允许列表**反转为**排除列表**（默认空）。
- `SourcePolicy`：`excludedBundleIDs`，空列表＝全部可读，被排除的应用拒绝。
- 设置界面：`Applications` 区块（空列表显示 "No applications excluded"，按钮 `Exclude Application…` / `Include Again`），
  OCR 说明文字同步改为 "an application you have not excluded"。
- 仍然拒绝的两类（没有放松）：**没有 bundle ID、无法归属的来源**（记为 `unknownOwner`）与
  密码框/安全控件（`blockedSensitive`）。排除的应用在**任何读取之前**就被拒绝，因此也到不了 OCR 兜底。
- 失败文案：`appNotAllowed` = "this application is excluded in Settings"。
- 缓存：`get(…excludedBundleIDs:)` 与 `removeAll(sourcesExcludedBy:)`；被排除后不再复用该来源的答案。

**升级安全（关键）**：旧允许列表 `HoverTranslate.allowedBundleIDs` **不迁移、不读取**；新键是
`HoverTranslate.excludedBundleIDs`。把旧列表当排除列表会静默屏蔽用户当初主动勾选的应用（TextEdit、Codex）。
测试 `SettingsStoreTests.testTheOldAllowListIsNeverReadAsAnExclusionList` 固定这条。

**文档同步**：`AGENTS.md` 与设计文档 §4 中"允许列表默认空"的规则已按本次用户授权改写（注明日期与原因）；
`docs/USER_GUIDE.md` §3/§8、`README.md`、`docs/RELEASE_NOTES.md` 同步。这是**行为约定的变更**，不是实现偏差。

**实测**：自动测试 **188 passed / 0 failed / 0 skipped**（v0.4 为 182）；新增 `SettingsStoreTests`(5)、
改写 `SourcePolicyTests` / `TranslationCacheTests` 为排除语义、`TranslationCoordinatorTests` 新增 2 项。
版本号为 0.5 / build 5。Release 与 Debug 构建、签名与启动见下方"构建证据"。

**未实测（需要用户手动）**：E 组真机项——从未添加过的应用能否直接取词、加入排除列表后是否真的不读、
升级后旧列表没有变成排除列表。

## v0.5 整改会话（2026-09-18）代码整改 + 回归

**范围**：外部只读审阅 `docs/PROJECT_REVIEW_2026-09-18.md` 的 R1–R7（R8 是真实环境验收，只能由用户执行）。
本轮**只做缺陷修复与文档收口，不新增功能、不递增版本号**；提交与发布不在本轮授权范围内。

**改动（按报告编号）**
- **R1 选区入口的来源**：`SelectionTextExtractor` 改为 `SelectionReading` 两段式——先 `focusedControl()`
  读焦点 AX 元素的 PID 与角色，再 `selectedText(belongingTo:)` 读正文（元素 PID 与确认时不一致则返回 nil）。
  协调器 `handleSelectionRequest` 在两者之间做来源策略：bundle ID 能否解析 → 排除列表 → 安全控件；
  读取完成后、发送前再次核对请求代次与**最新**排除列表。鼠标下的窗口不再被当作选区来源；
  `PointerWindowSourceLocator` 只服务于悬停路径。被排除/未知/受保护来源：读取 0 次、网络 0 次。
- **R6 失效流程**：`translationPolicyChanged` / `translationCredentialsChanged` / 新增的 `sessionWentInactive`
  都先 `cancelOutstanding` 并取消解释任务（使代次失效）再清缓存；`TriggerController` 把
  `screensDidSleep` 与 `sessionDidResignActive` 单独走 `sessionWentInactive`（切应用仍是 `externalChange`）。
  缓存写入仍受代次门约束，因此"清空之后又被旧结果写回"不会发生。
- **R2 不再预填剪贴板**：删除 `prefillManualFromClipboard()` 与 `revealManualWindow(Bool)`；
  新协议方法 `ManualPresenting.promptForManualPaste(_:)` 打开空编辑器并给出原因；菜单入口 `openManualEntry()`
  同样不为用户读剪贴板。
- **R5 手动 Copy 接线**：`ManualActionWiring.wire` 把 `manualActions.onCopy` 接到 `copyManualResult()`
  （原来是悬停卡片的 `copyDisplayedText()`）。
- **R3 日志**：`logTiming` 恢复插值；自动测试进程的实时日志实测 `stage=accessibility gen=1 ms=0 outcome=success`。
- **R4 快捷键注册**：`SelectionShortcutController` 改用 `CarbonHotKeyRegistrar`（`RegisterEventHotKey` +
  `InstallEventHandler` + `RemoveEventHandler`），状态机 `SelectionRegistrationState` 只有 idle/registered/conflict/failed；
  切换预设先释放旧组合，`stop()` 释放；菜单与设置共用 `summary(label:canReadSelection:)` 一套文案。
- **R7 文档**：本文件顶部新增唯一"当前状态"；`README.md`、设计文档 §3.3/§4/§8/§10、`docs/USER_GUIDE.md`、
  `docs/RELEASE_NOTES.md`、`docs/ACCEPTANCE.md` 与源码对齐（含 B07/B10 的旧引用与 F 组）。

**实测命令与结果**

```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination platform=macOS -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test     # 退出码 0，TEST SUCCEEDED，205 passed / 0 failed / 0 skipped
xcodebuild ... -configuration Release ... build   # 退出码 0，本项目源码 0 warning
log stream --style compact --level debug --predicate 'subsystem == "com.atat.HoverTranslate"'
#   → stage=accessibility gen=1 ms=0 outcome=success / stage=translation ... / stage=explanation ...
```

**测试类分布（2026-09-18 实测，共 205；xcresult 实读）**：TranslationCoordinatorTests 49、TranslationServiceTests 18、
CoordinateMapperTests 17、SentenceResolverTests 12、SelectionShortcutTests 10、TriggerPolicyTests 9、
TranslationCacheTests 9、TextResolverTests 9、OCRImageTests 7、OCRHitTesterTests 7、LearningStoreTests 7、
HoverDwellTests 7、TranslationRequestBuilderTests 6、SettingsStoreTests 5、OCRFallbackPolicyTests 5、
KeychainStoreTests 5、CardLifecycleTests 5、TextInputPolicyTests 4、RequestGateTests 4、ExplanationRequestBuilderTests 4、
SourcePolicyTests 3、PointerWindowPickerTests 3。
本轮新增/重写：`TranslationCoordinatorTests` +12（选区来源 6、单次按键 1、失效 4、手动 Copy 1）、
`SelectionShortcutTests` 由"事件匹配"改为"注册生命周期"（5 → 10 项）。

**Release 构建与启动实测（本次执行）**
- 产物 `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`，
  `CFBundleShortVersionString 0.5 / CFBundleVersion 5`、3.6 MB；`codesign --verify --deep --strict` 通过；
  designated requirement 不含 cdhash。
- 复制到 `/tmp/HTVerify/` 后**直接运行可执行文件**：10 秒无退出、无输出、`DiagnosticReports` 无新报告，
  随后主动结束该副本；**没有**影响用户当时正在运行的那一份（实测 `pgrep` 仍只有原来那一行）。
- 注册结果实测（R4 的真实证据）：`[com.atat.HoverTranslate:selection] selection shortcut Control-Command-T status=0`
  （0 = noErr，系统接受该组合）。
- **冲突路径未能实测**：本机没有第二个应用注册同一组合；实测**两份本应用实例**各自注册同一组合都返回 0，
  说明系统不把这种情况当冲突。可检测冲突的映射只有单元测试证据（`eventHotKeyExistsErr → .conflict`）。

## 未测与阻塞

### 2026-09-18 整改轮新增未测项（R8，全部 NOT RUN，需要用户手动）

- **快捷键冲突的真实提示**：实现已接入公开热键接口并能报告 `eventHotKeyExistsErr`，但本机没有可用的冲突对象——
  实测两份本应用实例同时注册同一组合都返回 0。需要用户用一个真实占用该组合的应用（或系统快捷键设置）
  验证"提示换一个组合"这条路径。
- **选区入口的真实端到端**：自动测试用假 `SelectionReading` 覆盖了"先策略、后读取"以及"读取期间换来源或被排除就丢弃"；
  真实应用里的焦点控件 PID/bundle ID 解析、密码框拒绝、焦点切换时的真实 AX 行为仍无实机证据。
- **剪贴板为 0 读取**：代码里已不存在自动读取剪贴板的路径（`prefillManualFromClipboard` 已删除，
  全库只剩 Copy 写剪贴板），但"打开手动窗口前后剪贴板不变"需要用户按 F 组自查。
- **锁屏清缓存**：`sessionWentInactive` 有自动化测试（缓存计数归零、在途结果不展示），
  但真实锁屏触发路径（系统通知投放与 TCC 行为）未实机取证。
- **R3 日志的真实样本**：已实测到可读的 `stage/gen/ms/outcome`，但**没有采集性能样本**，不提供任何延迟结论。

### v0.5 新增未测项（全部需要用户手动，均为 NOT RUN）

- **从未添加过的应用能否直接取词**：自动化只证明了策略与协调器行为（`testEveryApplicationIsReadWithoutAnExclusionList`），
  没有真机在"以前不在列表里的应用"上验过。
- **排除是否真的生效**：缺少真机证据，尤其是排除后菜单应显示 "this application is excluded in Settings"。
- **升级路径**：旧键写入后不会被当成排除项有自动测试，但"真机升级后第一次打开设置"没有实机取证。
- 排除的应用不会进入 OCR 兜底：这是结构性保证（排除在取词之前返回），未在真机核对截图计数。

### v0.3 新增未测项（全部需要用户手动，均为 NOT RUN）

- **真实整句取词**：只有字符串分句、边界完整性、协调器乱序的自动测试，**没有**在任何真实应用上核对取到的范围是否就是用户期望的那一句。
- **真实截图与 OCR**：需要用户授予屏幕录制权限才能执行，本次**未授权、未执行**。因此 `ScreenCaptureService` 的窗口过滤器、`sourceRect` 坐标约定（见"v0.3 实施会话"里的唯一假设）与真实返回像素尺寸**都没有实机证据**；现有证据只有纯逻辑测试、合成图片测试和注入假捕获的测试。
- **权限行为**：`CGPreflightScreenCaptureAccess()` 在未授权时的返回值、以及"拒绝后不弹窗、不绕过"的行为，目前只有代码审阅证据。
- **多屏 / Retina**：坐标转换有单测（1x/2x、负坐标、像素上限、窗口内夹取），但**没有外接屏实测**；本机只有内置屏，因此 C09 只能标"未测"。
- **阶段耗时**：代码已按阶段记录 `stage/gen/ms/outcome`，但**尚未采集真实 AX/OCR/API/cache 样本**（本次只跑了自动测试），性能记录仍为空，不提供任何延迟结论。
- **浮窗不出现在 OCR 输入里**：只有结构性论证（捕获过滤器只包含已确认的源窗口，浮窗属于另一个窗口），**未实机取证**。
- 已知实现成本：sentence 模式对每个悬停多做一次有界 `AXStringForRange`（最多 2000 单元）与一次 `AXBoundsForRange`；这是设计取舍，不是实测性能结论。

### v0.1/v0.2 遗留

- **需要用户手动**：真实软件取词；浮窗穿透的真实交互（点击穿透未测）；多屏摆放；"左右同按后只松右"的实机确认；滚动/切应用是否应关闭非 Pin 卡片（见上）。
- 真实取词目前只验证了"浮窗出现"这一条，**未逐项记录**：来源应用、`word`/`label` 判定、词框位置、快速换词不被覆盖、滚动/切应用失效等（ACCEPTANCE A 组其余行仍为 NOT RUN）。
- AX 取词路径（`AccessibilityTextExtractor`）此前只有编译与逻辑审查证据；2026-09-17 起有 1 条真机成功证据。
- ad-hoc 签名导致重新构建后需要重新授予辅助功能权限；若希望授权在重建后保持，可改用 Apple Development 身份签名（需用户指定账号与 team）。
- `hosting.fittingSize` 决定卡片高度，真实排版需人工确认是否截断。

> **2026-09-18 整改轮之后先做这件事**：按 `docs/ACCEPTANCE.md` 的 **F 组**在真机验证本轮四项改动
> （选区来源与三种拒绝、手动窗口不读剪贴板、手动 Copy、快捷键注册与冲突提示），再按 E 组验证全局可用与排除；
> 下面的 1–5 是 v0.5 当时的顺序，仍然有效。

## 下一步

1. **先用一次**：退出当前在跑的那一份，重新打开 Release 产物
   `$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app`，
   确认菜单栏只有**一个**图标（`pgrep -fl HoverTranslate` 只有一行）；打开设置确认 Applications 列表为空（"No applications excluded"）。
2. **先验 E 组**（v0.5 变更的核心）：在一个**从未添加过**的应用里悬停取词 → 用 `Exclude Application…` 排除它 →
   再悬停应失败，菜单显示 "this application is excluded in Settings" → 用 `Include Again` 去掉排除后恢复；
   并确认 TextEdit / Codex 没有出现在排除列表里（旧允许列表没有被迁移成排除项）。
3. 再按 `docs/ACCEPTANCE.md` 的 **D 组**操作（v0.4 的验收重点）：
   - D01 普通悬停/翻译/Pin 后，`Saved Entries…` 里不应出现任何条目；
   - D02 收藏一次 → `Quit HoverTranslate` → 重新打开 → 确认只剩下你保存过的那条；
   - D04 不点 `Explain` 时不应有解释请求（`log stream --predicate 'subsystem == "com.atat.HoverTranslate"'` 里不出现 `stage=explanation`）；
   - D05 手工把 `~/Library/Application Support/HoverTranslate/SavedEntries.json` 改坏 → 应用应提示且**不改动该文件** →
     点 `Delete All…` 才能恢复；
   - D06 `Clear cached translations` 后用同一个词复测，应重新请求；删 Key 后悬停与 Explain 都不再联网；
   - D07/D08 在 Release 产物上确认菜单栏可用、深浅色与长句排版可读。
4. 补 C 组与 B 组、A 组仍为 NOT RUN 的真机项（C01–C11、B01–B10、A01/A03/A04/A05/A08/A10/A11/A12）。
5. 四阶段计划到此结束：`docs/superpowers/plans` 里没有第五阶段，离线引擎、发音、自动复习等扩展在收到用户明确要求前不做。

## 每次续接必须更新

记录本次修改的具体文件、实际命令/工具和结果、最后通过的测试、当前失败、用户已完成的手动验收、下一条具体行动。
若路径/版本/签名变化，注明变化原因与对授权的实测影响。

## 会话结束记录格式

```text
日期及本机时区：
阶段与任务：
项目路径：
分支/提交：
改动文件：
构建或MCP证据：
自动测试：
手动验收：
阻塞与未测：
下一条行动：
```

## 会话结束记录

```text
日期及本机时区：2026-09-17，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.1 全部三个任务（工程/允许列表/触发；精确 AX 取词与坐标契约；请求失效与原文浮窗）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：master；代码提交 f8c9434（文档更新随下一次提交）
改动文件：新建 HoverTranslate.xcodeproj（含共享 scheme）、HoverTranslate/App(3)、Core(9)、Extraction(1)、Input(1)、Presentation(2)、Settings(2)、HoverTranslateTests(8)、.gitignore
构建或MCP证据：MCP 仅调用 XcodeListWindows（只读，返回 LightBalance 窗口）；构建/测试均为本机 xcodebuild，退出码 0
自动测试：49 passed / 0 failed（TriggerPolicyTests 5、HoverDwellTests 7、TextResolverTests 8、CoordinateMapperTests 6、RequestGateTests 4、SourcePolicyTests 4、CardLifecycleTests 5、TranslationCoordinatorTests 10）
手动验收：未开始（需要用户先授予辅助功能权限）
阻塞与未测：辅助功能授权、真实软件取词、浮窗真实交互、多屏摆放、左右 Option 实机区分
下一条行动：用户按 docs/ACCEPTANCE.md A 组实机验收后，再决定是否进入 v0.2
```

```text
日期及本机时区：2026-09-17，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.1 验收期缺陷修复（取词来源、失败文案、监视器可用性判定、失败诊断日志）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；修复提交 9203f45，签名变更 9a0ea09，tag v0.1（均已推送到 origin）
改动文件：HoverTranslate/{App/AppDelegate,Core/ExtractionSnapshot,Core/TranslationCoordinator,Extraction/AccessibilityTextExtractor,Input/TriggerController}.swift；HoverTranslateTests/{SourcePolicyTests,TranslationCoordinatorTests,TriggerPolicyTests}.swift；docs/PROJECT_STATUS.md、docs/ACCEPTANCE.md
构建或MCP证据：xcodebuild build（-derivedDataPath ~/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp）退出码 0；运行产物 cdhash ad59a5cb（重建后授权需重新授予，用户已重新授权）
自动测试：54 passed / 0 failed（TEST SUCCEEDED）
手动验收：真机悬停浮窗出现（用户确认）；其余 A 组未执行
阻塞与未测：来源应用/词框/穿透点击/Pin/多屏/左右 Option 区分仍未逐项实测；ad-hoc 签名导致每次重建后授权失效（待用户选 Apple Development 身份）；Chrome 不在允许列表
下一条行动：用户继续按 docs/ACCEPTANCE.md A 组验收；确认签名身份后可去掉重建即掉授权的问题
```

```text
日期及本机时区：2026-09-17，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.2 全部三个任务（DeepSeek 适配器与错误映射；Keychain/缓存/协调器接入；选区与手动粘贴入口）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；v0.2 代码与文档提交 **4c9e224**，tag **v0.2**（指向 4c9e224），文档续提交 1c8b0b8。
  **已推送**：远端 `refs/heads/main` = 1c8b0b8 = 本地 HEAD，`refs/tags/v0.2` = 26cc3a0（annotated）→ 4c9e224（实测 `git ls-remote origin` 核对）
改动文件：
  新增 HoverTranslate/Translation/{TranslationService,TranslationRequestBuilder,DeepSeekTranslationService}.swift
  新增 HoverTranslate/Core/{TranslationFailure,CacheKey,TranslationCache,TextInputPolicy}.swift
  新增 HoverTranslate/Settings/{KeychainStore,TranslationConfiguration}.swift
  新增 HoverTranslate/Extraction/SelectionTextExtractor.swift、HoverTranslate/Input/SelectionShortcutController.swift
  新增 HoverTranslate/Presentation/{ManualTranslationView,ManualWindowPresenter}.swift
  修改 HoverTranslate/{App/AppDelegate,App/HoverTranslateApp,App/MenuContentView,Core/ExtractionSnapshot,Core/TranslationCoordinator,Presentation/FloatingPanelController,Presentation/TranslationCard,Settings/SettingsView}.swift
  新增测试 HoverTranslateTests/{TranslationRequestBuilder,TranslationService,TranslationCache,TextInputPolicy,KeychainStore}Tests.swift
  修改 HoverTranslateTests/TranslationCoordinatorTests.swift、HoverTranslate.xcodeproj/project.pbxproj
  修改 docs/{PROJECT_STATUS.md,ACCEPTANCE.md}、README.md
构建或MCP证据：xcodebuild build（-derivedDataPath ~/Library/Developer/HoverTranslateDD）退出码 0、0 warning；
  MCP 本次未调用（XcodeListWindows 只返回 LightBalance 窗口，按项目边界不使用）
```text
日期及本机时区：2026-09-18，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：用户要求的"全局可用"后置变更（不在四阶段计划内）：来源策略由允许列表反转为排除列表
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；v0.5 提交 **c09b375**，tag **v0.5**（annotated，本地）。
  与 v0.4 一致：**没有 push**（v0.4 计划要求"不远程发布"，v0.5 沿用）；远端仍停在 9775a92
改动文件：
  修改 HoverTranslate/{Core/SourcePolicy,Core/TranslationCache,Core/TranslationCoordinator,Core/ExtractionSnapshot,Core/OCRFallbackPolicy,Settings/SettingsStore,Settings/SettingsView}.swift
  修改 HoverTranslateTests/{SourcePolicyTests,TranslationCacheTests,TranslationCoordinatorTests}.swift
  新增 HoverTranslateTests/SettingsStoreTests.swift；修改 HoverTranslate.xcodeproj/project.pbxproj（版本 0.5/build 5）
  修改 AGENTS.md、docs/superpowers/specs/2026-09-17-hovertranslate-design.md（§4 规则，注明日期与原因）
  修改 docs/{PROJECT_STATUS,ACCEPTANCE,RELEASE_NOTES,USER_GUIDE}.md、README.md
构建或MCP证据：Debug/Release 的 xcodebuild 退出码 0、本项目源码 0 warning；Release 0.5 codesign --verify --deep --strict 通过；
  designated requirement 不含 cdhash；MCP 本次未调用（按 AGENTS.md 项目边界）
自动测试：188 passed / 0 failed / 0 skipped（xcresult 实读）
手动验收：仅"Release 副本启动后稳定运行 12 秒、无崩溃报告"由代理执行；E 组真机项未执行
阻塞与未测：从未添加过的应用能否直接取词、排除是否真的生效、升级后旧列表是否被正确忽略（后两者有自动测试但无真机证据）
下一条行动：用户按 docs/ACCEPTANCE.md 的 E 组操作（先验证全局可取词与排除生效），再补 D/C/B/A 组真机项
```

自动测试：102 passed / 0 failed（TEST SUCCEEDED；xcresult total 102 / failed 0 / skipped 0）
手动验收：仅"新构建 .app 启动后稳定运行、无崩溃报告"这一条由代理执行；真实 API 与 GUI 交互未执行
阻塞与未测：需要用户输入自己的 DeepSeek Key 并点击 Test Connection；B 组实机项（悬停翻译、Ctrl+Cmd+T 选区、剪贴板不变）
  全部 NOT RUN；A 组 A01/A03/A04/A05/A08/A10/A11/A12 仍 NOT RUN
下一条行动：用户按 docs/ACCEPTANCE.md "B 组真实 API 验证步骤"操作；通过后确认是否进入 v0.3
```

```text
日期及本机时区：2026-09-17，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.3 全部三个任务（悬停整句与 partial 判定；OCR 兜底策略/单帧/词框定位；兼容性与性能收口）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；v0.3 代码与文档提交 **da63015**，tag **v0.3**（annotated）。已推送：远端 refs/heads/main = da63015，
  refs/tags/v0.3 已存在（实测 git ls-remote origin 核对）；v0.2 主线末尾为 708ae02
改动文件：
  新增 HoverTranslate/Core/{SentenceResolver,OCRFallbackPolicy,OCRHitTester}.swift
  新增 HoverTranslate/Extraction/{ScreenCaptureService,OCRTextExtractor}.swift
  新增测试 HoverTranslateTests/{SentenceResolver,OCRFallbackPolicy,OCRHitTester,OCRImage}Tests.swift
  修改 HoverTranslate/{Core/TriggerPolicy,Core/ExtractionSnapshot,Core/TranslationCoordinator,Core/TranslationFailure,Core/CoordinateMapper,Input/TriggerController,Extraction/AccessibilityTextExtractor,Presentation/FloatingPanelController,Settings/SettingsStore,Settings/SettingsView,App/AppDelegate,App/MenuContentView,App/HoverTranslateApp}.swift
  修改 HoverTranslateTests/{TriggerPolicyTests,TranslationCoordinatorTests,CoordinateMapperTests}.swift
  修改 HoverTranslate.xcodeproj/project.pbxproj、docs/{PROJECT_STATUS,ACCEPTANCE}.md、README.md
构建或MCP证据：xcodebuild build 退出码 0、本项目源码 0 warning；codesign --verify --deep --strict 通过；
  designated requirement 不含 cdhash（重建不需要重新授权辅助功能）；MCP 本次未调用（XcodeListWindows 只会返回 LightBalance 窗口，按 AGENTS.md 项目边界不使用）
自动测试：155 passed / 0 failed / 0 skipped（xcresult 实读：passedTests 155, failedTests 0, skippedTests 0）
手动验收：仅"新构建副本启动后稳定运行 12 秒、无崩溃报告"这一条由代理执行（用 /tmp 副本，未干扰用户正在运行的 v0.2 实例）
阻塞与未测：真实整句取词、真实屏幕录制授权与截图 OCR、多屏、A/B 组历史项全部 NOT RUN；
  SCK 的 sourceRect 坐标约定是唯一无法在无授权下实测的假设，修正点集中在 ScreenCaptureService.captureFrame
下一条行动：用户重启到新构建 → 按 docs/ACCEPTANCE.md C 组手动验收（尤其 C03/C04/C05 的截图调用计数）
```
```text
日期及本机时区：2026-09-17，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.4 两个任务（主动收藏与按需解释；设置收尾、回归与本机可运行应用）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；v0.4 代码与文档提交 **97273b1**，tag **v0.4**（annotated，本地）。
  **按 v0.4 计划"不远程发布"，本次没有 push**：远端仍是 v0.3 的状态（refs/heads/main = 9775a92）。需要同步时由用户执行 git push --follow-tags
改动文件：
  新增 HoverTranslate/Learning/{SavedEntry,LearningStore,LearningView}.swift
  新增 HoverTranslate/Translation/ExplanationRequestBuilder.swift
  新增测试 HoverTranslateTests/{LearningStore,ExplanationRequestBuilder,SelectionShortcut}Tests.swift
  修改 HoverTranslate/{Core/TranslationCoordinator,Translation/TranslationService,Translation/DeepSeekTranslationService,Translation/TranslationRequestBuilder,Input/SelectionShortcutController,Presentation/TranslationCard,Presentation/FloatingPanelController,Settings/SettingsStore,Settings/SettingsView,App/AppDelegate,App/HoverTranslateApp,App/MenuContentView}.swift
  修改 HoverTranslateTests/{TranslationCoordinatorTests,TranslationServiceTests}.swift、HoverTranslate.xcodeproj/project.pbxproj
  新增 docs/{USER_GUIDE,RELEASE_NOTES}.md；修改 docs/{PROJECT_STATUS,ACCEPTANCE}.md、README.md
构建或MCP证据：Debug 与 Release 的 xcodebuild 退出码均为 0，本项目源码 0 warning；Release 产物
  $HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app（0.4/build 4）codesign --verify --deep --strict 通过；
  designated requirement 仍不含 cdhash；MCP 本次未调用（XcodeListWindows 只会返回 LightBalance 窗口，按 AGENTS.md 项目边界不使用）
自动测试：182 passed / 0 failed / 0 skipped（xcresult 实读：passedTests 182, failedTests 0, skippedTests 0）
手动验收：仅"Release 副本启动后稳定运行 12 秒、无输出、无崩溃报告"由代理执行；其余 D 组项未执行
阻塞与未测：真实整句取词、屏幕录制授权后的截图 OCR、多屏、真实 API、剪贴板不变、深浅色与字号排版、
  Saved entries 的真机 UI 往返；A/B/C 组历史未测项保持原状
下一条行动：用户重启到 Release 0.4 → 按 docs/ACCEPTANCE.md D 组手动验收（收藏重启往返、Explain 只在点击后、清缓存后再请求、删 Key 后不联网）
```

```text
日期及本机时区：2026-09-18，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：v0.5 缺陷修复与验收收口（外部审阅 R1–R7；R8 保留给用户）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；HEAD 仍为 3888591（tag v0.5）。本轮改动**未提交、未推送、未发布**（审阅报告不授权这些动作）
改动文件：
  源码（9）：HoverTranslate/{Core/TranslationCoordinator,Extraction/SelectionTextExtractor,Input/SelectionShortcutController,Input/TriggerController,App/AppDelegate,App/HoverTranslateApp,App/MenuContentView,Presentation/ManualWindowPresenter,Settings/SettingsView}.swift
  测试（2）：HoverTranslateTests/{TranslationCoordinatorTests,SelectionShortcutTests}.swift
  文档（11）：README.md、docs/{PROJECT_STATUS,ACCEPTANCE,USER_GUIDE,RELEASE_NOTES}.md、
  docs/superpowers/specs/2026-09-17-hovertranslate-design.md、docs/superpowers/plans/ 下 5 个计划文件（加 2026-09-18 规则更新说明）
构建或MCP证据：xcodebuild Debug/Release 退出码均为 0、本项目源码 0 warning；Release codesign --verify --deep --strict 通过、
  designated requirement 不含 cdhash；Release 复制件实测启动 10 秒无退出；日志实测 selection shortcut Control-Command-T status=0；
  MCP 本次未调用（XcodeListWindows 只返回 LightBalance 窗口，按 AGENTS.md 项目边界不使用）
自动测试：205 passed / 0 failed / 0 skipped（TEST SUCCEEDED；v0.5 为 188）
手动验收：仅"Release 复制件启动 + 快捷键注册成功"由代理执行；F 组真机项与 E/D/C/B/A 组仍未执行
阻塞与未测：快捷键冲突无真实冲突对象可测（两份本应用实例不报冲突）；选区入口真实端到端、剪贴板不变自查、
  真实锁屏路径、真实 API、真实整句/OCR、多屏与排版、收藏 UI 往返均为 NOT RUN
下一条行动：用户按 docs/ACCEPTANCE.md 的 F 组操作并记录结果；如需提交/推送/发布，由用户单独授权后再执行
```

```text
日期及本机时区：2026-09-18，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：整句模式修饰键由 Shift 改为 Control（用户当场要求；属于 v0.5 工作区里的一项行为变更，未递增版本号）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；HEAD 仍为 3888591（tag v0.5）。本轮改动**未提交、未推送、未发布**
改动文件：
  源码（5）：HoverTranslate/{Core/TriggerPolicy,Core/TranslationCoordinator,Input/TriggerController,App/MenuContentView,Settings/SettingsView}.swift
  测试（2）：HoverTranslateTests/{TriggerPolicyTests,TranslationCoordinatorTests}.swift
    （TriggerPolicyTests 全部调用改为 control:；testShiftUpgradesTheModeToSentence → testControlUpgradesTheModeToSentence、
      testReleasingShiftReturnsToWordMode → testReleasingControlReturnsToWordMode、
      testShiftAloneIsNotATriggerAndDisabledStaysDisabled → testControlAloneIsNotATriggerAndDisabledStaysDisabled；
      TranslationCoordinatorTests 的 testReleasingShiftDropsTheSentenceRequestAndReturnsToWord → …ReleasingControl…，两处调用改 control:）
  文档（6）：docs/superpowers/specs/2026-09-17-hovertranslate-design.md §2/§3.1、docs/USER_GUIDE.md §3/§8、
    docs/ACCEPTANCE.md C01 与 C 组手动步骤、docs/RELEASE_NOTES.md、docs/PROJECT_STATUS.md、README.md
    （另有本会话新写的 docs/superpowers/plans/2026-09-18-v0.6-hover-selection.md 一并把 Shift 措辞改为 Control）
构建或MCP证据：xcodebuild Debug test 退出码 0（日志 .build/control-modifier-test.log）；本项目源码 0 warning；
  仅有的两条 warning 来自 appintentsmetadataprocessor（无 AppIntents 依赖，与本改动无关）；MCP 本次未调用
自动测试：205 passed / 0 failed / 0 skipped，** TEST SUCCEEDED **（与改动前基线一致：只改了断言与命名，未增删用例）
手动验收：无（真实按键与跨应用兼容性必须由用户操作；C01 实机仍为 NOT RUN）
运行实例（用户当场要求"重新构建再重启"）：按运行中实例所在的 DerivedData 重新构建 Xcode 默认路径的 Debug
  （$HOME/Library/Developer/Xcode/DerivedData/HoverTranslate-ewkbwpyycdbgikeccohiawihtlcp，** BUILD SUCCEEDED **、本项目源码 0 warning，
  日志 .build/control-modifier-xcode-dd-build.log）；核对 HoverTranslate.debug.dylib 含 "Hold Control as well"、无 "Hold Shift as well"；
  osascript quit 退出旧实例（PID 83442）后 open 启动新实例（PID 83845，实测运行 15 s 状态 S、只有一行进程、无崩溃报告）。
  HoverTranslateDD 下的 Debug/Release 两份同版本产物此前已分别构建（03:55 / 03:56），本次未再触碰；
  两处路径的产物**不得同时运行**（会出现两个菜单栏图标，辅助功能授权只会落在其中一份）。
阻塞与未测：Control+Option 与 VoiceOver 默认组合键是否冲突**未实测**（本机未启用 VoiceOver）；
  "Shift 不再切换模式"这一条只有类型层面的保证（TriggerPolicy 已无 shift 参数），没有事件级自动化测试
下一条行动：用户按 docs/ACCEPTANCE.md C 组复测整句（触发键 + Control）；如需提交/推送/发布，由用户单独授权后再执行
```

```text
日期及本机时区：2026-09-18，Asia/Shanghai（工具输出时间戳 +0800）
阶段与任务：悬停可靠性修复（依据 docs/HOVER_RELIABILITY_DIAGNOSIS_AND_FIX_PLAN_2026-09-18.md 的 R1–R4）
项目路径：/path/to/HoverTranslate_Execution_Pack
分支/提交：main；HEAD 仍为 3888591（tag v0.5）。本轮改动**未提交、未推送、未发布**；
  按诊断文档 §2.7 也**未替换正在运行的应用**（运行实例仍是本轮之前的构建）
改动文件：
  源码（5）：HoverTranslate/Extraction/AccessibilityTextExtractor.swift（R1：命中与字符定位共用一次 AppKit→AX 转换；
    新增 AXControlReading 接缝与命中日志）、HoverTranslate/Core/OCRFallbackPolicy.swift（R2：earliestStart + 等待文案）、
    HoverTranslate/Core/TranslationCoordinator.swift（R2 有界补试与取消、R4 状态与节流、R3 失败原因日志）、
    HoverTranslate/Presentation/FloatingPanelController.swift 与 Presentation/TranslationCard.swift（R4 状态展示）
  测试（2 + 工程登记）：新增 HoverTranslateTests/AccessibilityTextExtractorTests.swift（12 项，含假 AX 控件）；
    HoverTranslateTests/TranslationCoordinatorTests.swift 新增 9 项（R2/R4）；HoverTranslate.xcodeproj/project.pbxproj 为新文件登记 4 处
  文档（5）：docs/{ACCEPTANCE,PROJECT_STATUS,USER_GUIDE,RELEASE_NOTES}.md、README.md
    （另：docs/superpowers/plans/2026-09-18-v0.6-hover-selection.md 同步说明接缝已就绪）
构建或MCP证据：xcodebuild Debug test 退出码 0、** TEST SUCCEEDED **（日志 .build/final-reliability-test.log）；本项目源码 0 warning；
  红证据：临时还原 R1 缺陷后这 4 条坐标测试真实失败（.build/r1-red-proof.log），随后恢复并复测通过；MCP 本次未调用
自动测试：226 passed / 0 failed / 0 skipped（本轮 +21：AX 命中路径 12、OCR 有界补试与取消 7、状态反馈 2；历史 205 项全部保留且未放宽）
手动验收：无。真机项（H 组 7 步、Chrome 正文与导航、多屏、真实 OCR 补试、状态文案与摆放）全部 NOT RUN，必须由用户操作
未完成/限制：R3 的"短链接/静态标签兼容路径"**未实现**——按文档要求先采集真实 role 与映射类别再决定；本轮只补齐诊断日志
  （hit role=… mapping=…、extraction failed reason=…）；PointerWindowPicker 的 layer==0 过滤未改动
下一条行动：用户在真机按 H 组操作并采集 R3 证据（不改浏览器或系统权限）；如需替换正在运行的实例或提交，由用户单独授权
```

## v0.6 实施会话（2026-09-18）悬停已选中文本

计划：`docs/superpowers/plans/2026-09-18-v0.6-hover-selection.md`，任务 1–4 全部完成（勾选已更新）。
本轮开工前先做了一件事：把 v0.5 整改轮的 36 个改动提交为本地提交 `08d94c5`（**未推送**），
因此基线不是计划里写的 205，而是实测 **233**。

```text
版本/任务：v0.6 悬停已选中文本（任务 1–4 完成；真机 G 组 NOT RUN）
项目完整路径：/path/to/HoverTranslate_Execution_Pack
当前分支与提交：main；HEAD = 08d94c5（v0.5 整改轮，未推送）；**v0.6 改动未提交**
修改文件及目的：
  新增（2）：HoverTranslate/Core/SelectionHitPolicy.swift（纯函数：矩形包含 + UTF-16 序号相交，容差 2pt，只覆盖像素取整）；
    HoverTranslateTests/SelectionHitPolicyTests.swift（7 项）
  修改（7）：HoverTranslate/Extraction/AccessibilityTextExtractor.swift（AXControlReading 接缝新增 focusedControl()/
    selectedRange(of:)/selectedText(of:)，SystemAXControls 对应实现；read 在辅助功能权限门之后、命中接口之前插入一次
    选区探测，任何失败返回 nil 继续原路径、不抛错）；
    HoverTranslateTests/AccessibilityTextExtractorTests.swift（假控件支持"焦点元素与命中元素不同"及其各自 owner/选区；
    新增 11 项探测测试）；HoverTranslateTests/TranslationCoordinatorTests.swift（新增 1 项接线测试）；
    docs/ACCEPTANCE.md（G 组 11 项 + 手动步骤）；docs/USER_GUIDE.md（用法表 +1 行、已知限制 +4 条）；
    docs/superpowers/specs/2026-09-17-hovertranslate-design.md（§3.1 隐私边界、§3.3 两个选区入口的区别）；
    HoverTranslate.xcodeproj/project.pbxproj（两个新文件各登记 4 处；版本 0.6/6）
实际构建命令：xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" test
构建退出码：0；Release 亦退出码 0，codesign --verify --deep --strict 通过；产物版本 0.6 / 6
测试命令与通过/失败/跳过数量：252 passed / 0 failed / 0 skipped（xcresult 实读；基线 233，本轮 +19＝策略 7 + 探测 11 + 接线 1）
红灯证据：先只写 SelectionHitPolicyTests 时真实失败——cannot find 'SelectionHitPolicy' in scope、退出码 65
  （日志 .build/v0.6-task1-red.log）；实现后同一条命令退出码 0（.build/v0.6-task1-green.log）
已实际运行的交互验证：无。真机项只能由用户执行
待用户验证的项目：ACCEPTANCE G01–G11 全部 NOT RUN
未完成/不兼容/阻塞：R3 的短链接/静态标签兼容路径仍未实现（沿上一轮，先采集真实 role 与映射类别再决定）；
  不使用 AXRangeForPosition 的应用里多行选区边缘可能偏宽（已如实写进指南）；G09 需要用户逐应用登记真实 AX 能力；
  计划里"若悬停延迟明显变差再加 0 次 AX 调用的前置门"未做——G11 尚无实测数据，不做未经验证的优化
应用启动路径：$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app
下一步：用户按 G 组真机验收；v0.6 是否提交由用户单独授权。按计划 §8 停止点：任务 4 结束即停止，不自动开始下一版。
  下一版（Apple 本地翻译 + 内置词库）的计划尚未写入仓库。
```

口径说明：探测只在"触发键按住 + 指针稳定"之后发生；只向焦点控件询问选区范围与屏幕矩形；只有指针确实落在选区内
才读取正文。判定（纯函数）与 AX 接线分离，所以规则可以用假控件复现，不需要真实辅助功能授权。
```

## v0.7 实施会话（2026-09-19）单词的词性与多个意思

用户需求："增加对应单词的词性解释和更多的意思，大概列出三个就行，如果这个单词有多种词性则依次列出。"
数据来源在 v0.6 之后单独确认过：**随包的离线词库**（ECDICT，MIT，见 `docs/THIRD_PARTY_NOTICES.md`），
展示规则也由用户确认（单个单词、按词性顺序、每词性最多 2 条、总数封顶 3 条、保留 `[计]`/`[法]` 语域标签）。

```text
版本/任务：v0.7 离线词库（单词词性 + 多个意思）；真机 I 组 NOT RUN
项目完整路径：/path/to/HoverTranslate_Execution_Pack
当前分支与提交：main；HEAD = c919289（feat(v0.6)，未推送）；**v0.7 改动未提交**
数据：HoverTranslate/Resources/WordBook.tsv（2.03 MB，43342 条，考试大纲词 ∪ 词频≤5 万）
      HoverTranslate/Resources/WordBookLemmas.tsv（0.59 MB，35171 条 变形→原型）
      由 tools/build-wordbook.py 从 ecdict.csv 生成；生成脚本与许可说明一并入库
改动文件：
  新增：Dictionary/WordBook.swift（解析 + 上限规则）、Dictionary/WordSenseProvider.swift（协议 + actor 懒加载）、
    HoverTranslateTests/WordBookTests.swift（11 项）、两个数据文件、tools/build-wordbook.py、docs/THIRD_PARTY_NOTICES.md
  修改：Core/TranslationCoordinator.swift（注入 senses、按 scope==.word 查询、代次校验、两处取消）、
    App/AppDelegate.swift（真实注入 BundledWordBookProvider）、Presentation/FloatingPanelController.swift（setDictionary + present 重置）、
    Presentation/TranslationCard.swift（词典段 + 行格式）、HoverTranslateTests/{TranslationCoordinatorTests,SelectionShortcutTests}.swift、
    docs/{ACCEPTANCE,USER_GUIDE,PROJECT_STATUS,RELEASE_NOTES}.md、设计文档、project.pbxproj（**新增 Resources 构建阶段**）、
    README（数据与验收分组）
工程坑（已记录）：Xcode MCP 的 XcodeWrite 对 `HoverTranslate/Resources/x.tsv`、`HoverTranslate/Dictionary/x.swift` 这类
  "工程里还不存在该子分组"的路径，会把文件创建到**仓库根目录**（`<repo>/Resources/`、`<repo>/Dictionary/`），
  而且非源码文件不会被加进任何 target。已按需手工修正 pbxproj：文件引用、分组归属、Resources/Sources 成员各 4 处。
实测命令与结果：
  红：xcodebuild … -only-testing:HoverTranslateTests/WordBookTests test → cannot find type 'WordBook'，退出码 65
  绿：同上命令 → 11 passed，退出码 0
  全量：xcodebuild … test → TEST SUCCEEDED，退出码 0，**265 passed / 0 failed / 0 skipped**（xcresult 实读）
手动验收：无。真机项 I01–I10 全部 NOT RUN
未完成/限制：只对单个单词生效；不做语境判断/例句/音标；ECDICT 数据来源混合、未逐项声明许可（已如实写进 THIRD_PARTY_NOTICES）
应用启动路径：$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app（0.7/7）
下一步：用户在真机按 I 组验收；v0.7 是否提交由用户单独授权。之后才是用户最初那份规划里的
  "Apple 本地翻译（免 Key 默认）"部分——它还没开工，规划文件也还没写进仓库。
```

## 2026-09-20 实施会话：网页命中可靠性与跨行整句（设计文档 2026-09-19）

**范围**：`docs/superpowers/specs/2026-09-19-web-hit-and-cross-line-sentence-design.md` 的 §3（网页命中）与 §4（统一跨行句子边界）。
**不改**翻译引擎、收藏、词库、来源策略、排除列表与剪贴板规则。**未递增版本号**（仍是 0.7/7）：本轮与 v0.7 在同一个未提交工作区里。

**改动**
- `Core/SentenceContextNormalizer.swift`（新）：同一段里的**单个换行**（含两侧空白；CRLF 记一次换行）压成一个空格，
  **两个及以上换行（空行）原样保留**作为段落边界；同时保存"规范化 UTF-16 偏移 → 原文 UTF-16 范围"的逐单元映射，
  两个方向都能查（`originalRange(forNormalized:)`、`normalizedOffset(forOriginal:)`）。
- `Core/SentenceResolver.swift`（重写）：输入变成 `SentenceWindow`（文本 + 起点是否就是元素开头 + 终点是否就是元素结尾；
  OCR 用 `.fragment`，两端都不可证明），返回 `Resolution`（原文范围、单行文本、complete/partial、**不含正文的边界类别**
  `complete`/`clippedStart`/`clippedEnd`/`missingTerminator`/`missingBoundary`）。设计 §4.2 要求的"不再只返回 NSRange"由此落地；
  旧的 `sentence(in:atUTF16Offset:)`、`sentenceRange`、`isComplete` 已删除（不再有调用者）。
- `Extraction/AccessibilityTextExtractor.swift`：
  - 短控件角色新增 `AXDisclosureTriangle`；标签按 `title` → `value` → **新增 `description`** → **唯一直接文字子节点**
    的顺序读取。子节点最多 8 个、只查一层、必须同 PID、也不是受保护控件、矩形与父控件相交、且是文字角色
    （`AXStaticText`）；**两个非空候选就放弃**，不拼接。整页 AX 树一行都不遍历。
  - 短控件新增前置条件：**控件矩形有效且指针在矩形内**（此前 `boundedLabel` 完全不看矩形）。这是设计 §3.2 的明确要求，
    但它使 `AccessibilityTextExtractorTests.testAShortControlStillAnswersWithItsWholeLabel` 里那个"指针并不在其中的假控件"
    必须换成真正包含指针的矩形（断言本身未改）。真实应用里"短控件不报矩形"会从"能读标签"变成"读不到"，已登记为 J10。
  - 整句走统一解析器：窗口文本 + `windowStart` + `elementEnd` 交给 `SentenceResolver`，原文范围用于 `AXBoundsForRange` 锚点，
    `completeness` 直接来自边界判定。新增两条**类别**日志：`short control role=… origin=…`、`sentence boundary=…`（不含正文）。
- `Core/OCRHitTester.swift`：新增 `contextLines(containing:lines:)`——有界的同行/相邻行几何分组（最多 6 行）。
  只有同时满足"该行在自己的行带里没有别的观察结果（双栏与表格单元格会同时出现）、行距像正常行距、
  水平范围重叠 ≥ 较窄者一半、阅读方向一致"的相邻行才会接上。语言边界仍然只在 `SentenceResolver` 里判定。
- `Extraction/OCRTextExtractor.swift`：新增 `OCRContext`（把行块拼成局部文本：行间换行、词间空格，并记录每个词的范围；
  上限 2000 UTF-16 单元，放不下的行整行丢弃、不切断）；整句模式改用统一解析器，失败时才回落到原来的"单行 + partial"；
  **识别器新增 `OCRWord.trailing`**（`.byWords` 会去掉标点，导致拼出的句子没有终止符、送翻译的原文丢标点；
  现在词后的标点单独保存，**词模式返回的仍然只是那个词**）。
- `project.pbxproj`：新增 1 个 Swift 文件（fileRef + Core 分组 + app Sources，共 3 处；沿用 v0.7 记录的"手工改 pbxproj"做法）。

**红/绿证据（本次真实执行）**
```bash
cd "/path/to/HoverTranslate_Execution_Pack"
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination platform=macOS -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test -only-testing:HoverTranslateTests/SentenceResolverTests > .build/webhit-red.log 2>&1
# 红：退出码 65；error: 'Resolution' is not a member type of enum 'HoverTranslate.SentenceResolver'（新 API 尚不存在）
xcodebuild ... test > .build/webhit-green2.log 2>&1
# 绿：退出码 0，TEST SUCCEEDED，301 passed / 0 failed / 0 skipped（xcresult 实读；265 → 301，+36）
xcodebuild ... -configuration Release build    # 退出码 0，本项目源码 0 warning（.build/webhit-release.log）
codesign --verify --deep --strict <Release 产物>   # valid on disk / satisfies its Designated Requirement（0.7/7）
```
分项（本轮新增或重写）：`SentenceResolverTests` 12 → **26**（规范化与双向偏移映射 8、句子与边界 18，含缩写/小数/域名/中文标点/引号/emoji、
双换行不跨段、窗口两端裁切、fragment 两端不可证明）；`OCRHitTesterTests` 7 → **15**（行块分组：折行可合并、可向上扩展、
双栏/表格/大间距/大跳跃断开、行数上限）；`OCRImageTests` 7 → **10**（真实 Vision 的两行整句 complete、捕获边缘 partial、
脚本化识别的跨行锚点并集）；`AccessibilityTextExtractorTests` 新增 14（短控件：唯一文字子节点、文字与内边距同一标签、
候选顺序 title/value/description、两个候选/超长/多行/不相交/异 PID/非文字角色拒绝、受保护子节点 0 读取、
指针不在矩形内 0 读取、最多 8 个子节点且全部释放；整句：跨行整句 complete、窗口裁切 partial）。

**过程中发现并修掉的真实缺陷（不是放宽测试）**
1. **OCR 丢标点**：`candidate.string.enumerateSubstrings(options: .byWords)` 返回的词不含标点，第一轮 5 个红灯里有 3 个由它引起——
   拼出的句子没有句末标点，边界永远无法证明，送翻译的原文也丢标点。修法是给词加 `trailing`（词模式不受影响）。
2. **右边界判定**：`NLTokenizer` 的 token 含尾随空格，旧 `isComplete` 把"句子结束位置 == 窗口长度"当成"被裁"。
   新实现改为"句子以有效终止符结尾即可证明右边界"，窗口是否被裁只在**没有**终止符时用于区分类别。
3. 一条测试自身的期望值算错（锚点并集漏算了下一行起始词的 x），属于测试 bug，按实际并集改正。

**偏差（如实登记）**
- 设计 §4.4 的"按纵向位置聚类文字行"没有实现成聚类算法，而是**从命中的行块向上下逐行扩展**，判定条件即上面四条几何规则 + 行带独占。
  双栏、表格（每格一个观察结果）、大间距、大跳跃都有自动测试固定；**表格若被识别成一整行，几何上与折行段落不可区分，此时宁可断开**
  （结果是 partial）。这是设计 §6"不确定就停止连接"的保守一侧，不是遗漏。
- OCR 的锚点是"这句话覆盖的词框并集"，没有做更精细的逐行矩形。
- 设计 §8 的非目标一条未动：没有最近单词搜索、没有扩大容差、没有整页 AX 遍历、没有整屏 OCR。

**未测试/限制（NOT RUN，必须由用户操作）**
- Google Workspace 顶部 `Solutions / Products / Industries`：文字笔画与内边距是否给出同一标签**未实测**（J01–J03）。
- `AXDisclosureTriangle` 的真实角色名、真实 `AXChildren` 形态、真实 `AXDescription` 内容：只有假控件证据，无实机证据。
- 真实网页正文的跨行整句范围、缩写/域名边界：只有字符串级证据（J05–J07）。
- 双栏/表格页面的真实截图与真实排版：只有合成图片与脚本化识别证据（J08）。
- 短控件"必须报矩形"带来的行为变化（J10）需要实机核对是否影响任何常用应用。
- Release 复制件启动抽查：**本轮未运行**（不启动第二份实例，避免与用户正在运行的那一份混淆）。
- 提交/推送/发布：未授权，未执行。

