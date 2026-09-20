# HoverTranslate 四阶段总执行方案 Implementation Plan

> **For agentic workers:** 若当前环境已提供 superpowers，使用 `superpowers:executing-plans` 按任务执行；可独立审查的任务可使用 `superpowers:subagent-driven-development`，但本项目默认单主会话、串行写入。未安装这些技能时按本文件逐项执行，不为满足技能名称擅自安装插件。以 `- [ ]` 跟踪真实完成状态。

> **2026-09-18 更新（当前规则）**：本计划写于"允许列表默认空"时期。来源策略已在 2026-09-18 按用户要求反转为
> **排除列表默认空**——默认**所有应用**都可读，设置里只能逐个排除；无法归属来源与密码/安全控件仍然拒绝。
> 以 `AGENTS.md` 与设计文档 §4 为准；本文中出现"允许列表"的地方属于当时的历史记录，不再是当前规则。


**Goal:** 交付用户本机自用、可验证的按键悬停翻译应用。

**Architecture:** SwiftUI 设置/内容 + AppKit 菜单栏/浮窗 + AX 优先取词；第二阶段接入翻译，第三阶段增加本机 OCR。

**Tech Stack:** Swift、SwiftUI、AppKit、ApplicationServices；按阶段加入 Foundation URLSession、Security、NaturalLanguage、ScreenCaptureKit 和 Vision。

**Spec:** `docs/superpowers/specs/2026-09-17-hovertranslate-design.md`

## Global Constraints

- 独立 macOS 原生项目，暂名 HoverTranslate；不属于 Light Balance。
- Swift + SwiftUI + AppKit；部署目标设计为 macOS 14.0，必须由本机 SDK 核对可用性。
- 第一轮只执行 v0.1；每个版本提交实测报告后停止，不自动跨版本。
- 默认右 Option 悬停；设置提供左右 Option 选择；不吞掉或重放原应用事件。
- 仅按用户明确触发读取；应用**排除列表**默认空（2026-09-18 起：默认所有应用可读）；不默认截图、联网或保存原文。
- 不碰 Light Balance、Harness 配置、系统安全策略或其他项目。
- 使用当前发现的 Xcode MCP 工具；不得猜测工具名、参数或已完成操作。
- 普通日志不得包含原文、译文、截图、密钥、HTTP 请求体或响应体。
- 测试使用合成数据；构建成功不代表跨应用交互通过。
- 所有时间、上限和阈值都是设计初值，不是已经测出的性能。

---

## 0. 执行前已经确定的事项

用户确认 DeepSeek Harness → Xcode MCP 连接已跑通。不要再配置接口。
本包是计划，不是已经完成的项目。第一轮只做 `docs/superpowers/plans/2026-09-17-v0.1-foundation.md`。
采用独立目录与独立 Git 仓库，绝不与 Light Balance 混用。

## 1. 四阶段路线

| 版本 | 唯一核心交付 | 进入下一版的条件 |
|---|---|---|
| v0.1 | 按住键、准确取得英文、显示原文卡片 | 实际运行；至少一个外部原生应用的词/标签取词通过，失败软件如实登记 |
| v0.2 | 英中单词/标签和主动选区翻译 | 假网络自动测试通过；用户完成一次真实 API 验证；取消/缓存/Keychain通过 |
| v0.3 | 悬停整句与局部 OCR | 合成图像和目标软件验收；空白/双栏/隐私禁止情形无误翻 |
| v0.4 | 主动学习、设置完善、本机交付 | 回归矩阵明确；应用可按给定路径启动；已知限制与未测项写清 |

## 2. 工程结构

```text
HoverTranslate/
├── AGENTS.md
├── README.md
├── HoverTranslate.xcodeproj/
├── HoverTranslate/
│   ├── App/                 # AppDelegate、菜单栏、设置入口
│   ├── Core/                # 值类型、状态机、词/句解析、坐标、缓存键
│   ├── Input/               # Option 状态与显式选区快捷键
│   ├── Extraction/          # AX；第三阶段才加入 OCR/截图
│   ├── Translation/         # 服务协议、DeepSeek适配、请求构造
│   ├── Presentation/        # NSPanel与SwiftUI卡片
│   ├── Settings/            # 设置、排除列表、Keychain
│   └── Learning/            # 第四阶段才创建
├── HoverTranslateTests/     # 纯逻辑、假服务、合成图片测试
├── docs/
│   ├── PROJECT_STATUS.md
│   ├── ACCEPTANCE.md
│   ├── REFERENCES.md
│   └── superpowers/...
└── .build/                  # DerivedData和测试结果；不提交
```

按阶段创建需要的文件；不要先建立大量空类或无功能界面。
假定主 target/module/scheme 统一命名 `HoverTranslate`，测试 target 命名 `HoverTranslateTests`。
已有工程命名不同则先记录映射并一致调整计划中的命令，不要新建第二份重复工程。

## 3. 环境核对与工程创建

先检查（只读）：
```bash
pwd
git status --short
git rev-parse --show-toplevel
sw_vers
xcodebuild -version
xcode-select -p
```

非 Git 目录的相关命令失败是正常结果，记录后在独立目录建立本地仓库，不扫描其他项目。
通过已发现的 MCP 工具列出打开的项目，核对操作对象是本项目完整路径，不按同名窗口盲选。
优先使用已有的创建/文件工具建立标准 macOS App 项目。
若 MCP 不支持创建新项目、且终端没有已经可用的项目生成工具，不擅自安装：只需用户在 Xcode 建一次模板：
`File → New → Project → macOS → App`，名称 HoverTranslate，SwiftUI、Swift、无持久化模板，保存到独立根目录并避免多套一层重复目录。
初始化完成再由代理继续实施。不要伪造 .xcodeproj 已创建。

## 4. 构建和测试的真实证据

工程建立后先实际列出 scheme：
```bash
xcodebuild -list -project HoverTranslate.xcodeproj
```

标准构建：
```bash
xcodebuild -project HoverTranslate.xcodeproj \
  -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build
```

标准测试：
```bash
xcodebuild -project HoverTranslate.xcodeproj \
  -scheme HoverTranslate -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData test
```

每个测试任务可加 `-only-testing:HoverTranslateTests/具体测试类名`。文档中列明类名。
必须记录真实退出码；输出经管道时使用 `set -o pipefail`，不能只看到日志工具退出零就当构建成功。
也可以使用实际 MCP 构建/测试工具，记录工具名、工程路径、返回结果；不得虚构工具 ID。
不默认加 `CODE_SIGNING_ALLOWED=NO` 掩盖运行与授权问题。
若没有 GUI 执行工具，给出实际生成 .app 的位置与一次用户打开操作，GUI项标待测。

## 5. 阶段内的工作粒度

每次只完成一个可单独验收的任务。自动测试代码片段位于对应计划，是实现契约；其依赖的类需要由代理按规格创建。
每个任务执行红→绿→重构；运行失败要区分“预期测试红灯”“环境阻塞”和“实现错误”。
GUI部分不以假自动化冒充；纯逻辑先测试，然后给用户明确的手动操作。
每阶段最后检查 `git diff --check` 和 `git status --short`，只提交本任务文件。
不要修改测试断言来掩盖真实行为错误，不要把测试标 skip 后声称全部通过。

## 6. 每阶段的固定交付报告

```text
版本/任务：
项目完整路径：
当前分支与提交：
修改文件及目的：
实际构建命令或MCP工具：
构建退出码：
测试命令与通过/失败/跳过数量：
已实际运行的交互验证：
待用户验证的项目：
未完成/不兼容/阻塞：
应用启动路径：
下一步：
```

`docs/PROJECT_STATUS.md` 记录当前状态；不要让下一会话依赖本次聊天记忆。
若用户中途停止，先保存真实文件和未完成状态，不擅自提交不完整功能为“完成版本”。
