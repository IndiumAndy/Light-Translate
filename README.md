# Light Translate

**按住一个键，把鼠标停在英文上，中文就地出现——不切窗口、不复制粘贴、不打开浏览器。**

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![language](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-orange)
![license](https://img.shields.io/badge/license-MIT-green)

Light Translate 是一个 macOS 菜单栏应用（不显示 Dock 图标、不安装后台服务、不做账号）。
它读取你**当前正在看**的那段英文，用一个浮动小卡片给出中文翻译；
翻译请求走**你自己的 DeepSeek API Key**，词典数据**完全离线**。

---

## 它解决什么问题

读英文时被打断的代价，往往比那个词本身大得多：切窗口、选中、复制、开浏览器、粘贴，
再切回来——注意力已经断了。Light Translate 把这一步压成"按住 + 停一下"：

```
按住右 Option ──▶ 鼠标停在英文上 250 ms ──▶ 卡片就地显示中文 ──▶ 松键消失
```

| 传统做法 | Light Translate |
|---|---|
| 切到浏览器 / 词典 App | 原地浮窗，当前应用不失去焦点 |
| 选中 → 复制 → 粘贴 → 清剪贴板 | 松键即走，**不碰剪贴板**（只有你点 Copy 才写） |
| 事后回想"刚才那个词" | 直接 `Save` 收藏，或 `Explain` 问当前语境下的意思 |

## 特点

- **精确取词，不猜。** 通过辅助功能（Accessibility）读取指针下**真实存在**的那个词。
  拿不到就明说原因（例如 `no exact text at this position`），**不会**退而求其次给你"最近的词"。
- **整句模式。** 按住触发键的同时按住 **Control**，读整段句子而不是单词；
  同一段里的排版折行不再截断句子，空行（段落边界）才断开，`Dr.`、`3.14`、`example.com` 不会误判为句末。
- **选区翻译。** 在任意应用里选中英文，按全局快捷键（默认 `Control-Command-T`）直接翻译整段。
- **悬停已选中的文本。** 已经选好一段？不用快捷键，直接把指针移到选区上停住即可。
- **离线词典，标注来源。** 单个单词会额外显示**词性与多个中文释义**（约 4.3 万条常用词，随应用分发、断网可用），
  并明确标为 `Dictionary · On-device`，与 AI 译文分开，**不冒充**词典。
- **按需解释。** `Explain` 只解释这个词**在当前这句话里**是什么意思，卡片上标明是 AI 解释、不是词典条目。
- **失败可见。** 读不到、被排除、权限不足都会短暂说明原因，不会静默什么都没发生。
- **隐私默认收紧。** 只有你按住触发键时才读取；不上传截图；缓存只在内存；密码框永不读取。
- **无账号、无云同步、无自动更新、无开机常驻、无付费墙。**
- **301 项自动化测试，0 失败 / 0 跳过**（2026-09-20 实测，命令见下方"开发与测试"）。

## 系统要求

- macOS **14.0** 或更高（Sonoma 及以上）
- Xcode 26.x（仅构建时需要；直接用已构建好的 .app 则不需要）
- **没有任何第三方依赖**——全部使用系统框架（SwiftUI / AppKit / ScreenCaptureKit / Vision / NaturalLanguage）

## 构建与运行

```bash
git clone https://github.com/IndiumAndy/Light-Translate.git
cd Light-Translate

# Release 构建
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Release \
  -destination platform=macOS -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates build

# 运行
open "$HOME/Library/Developer/HoverTranslateDD/Build/Products/Release/HoverTranslate.app"
```

也可以直接用 Xcode 打开 `HoverTranslate.xcodeproj` 后按 ⌘R。

> 关于命名：应用的显示名是 **Light Translate**，但 Xcode 工程、target、scheme 与 bundle ID 仍保留 `HoverTranslate`。
> 这是因为改动 bundle ID 会让系统的辅助功能/屏幕录制授权失效，并且已保存的 API Key 与设置会丢失。
> 所以下面命令里的工程名与产物路径仍然是 `HoverTranslate`，这是有意为之，不是笔误。

> 关于签名：仓库里的工程**没有写死开发者 Team**，直接构建会报
> `Signing for "HoverTranslate" requires a development team.`。两种做法选一个：
> 用 Xcode 打开后在 target → `Signing & Capabilities` 里选你自己的 Team；
> 或者在命令行末尾追加上 `DEVELOPMENT_TEAM=<你的 Team ID>`（已实测可用，不会改动工程文件）。
> 这一步不能省：只有稳定的签名身份，辅助功能/屏幕录制授权才能在重建后继续有效；
> 换成 ad-hoc 签名每次重建都会掉权限。

> ⚠️ **DerivedData 一定要放在项目目录之外。**
> 如果项目放在 iCloud / FileProvider 管理的目录里（例如桌面、文稿），把 DerivedData 放在项目内会导致**签名失效**：
> 签名完成后系统又写回 `com.apple.FinderInfo`，`codesign --verify` 会报
> `resource fork, Finder information, or similar detritus not allowed`。
> 上面命令里的 `$HOME/Library/Developer/HoverTranslateDD` 就是为此。

### 首次使用：两个权限

| 权限 | 是否必需 | 作用 |
|---|---|---|
| **辅助功能**（Accessibility） | **必需** | 观察触发键、读取指针下的文字与选区 |
| **屏幕录制**（Screen Recording） | 可选，默认关闭 | 仅当目标应用无法通过辅助功能报告文字时的 OCR 兜底 |

两个权限都由**你手动授予**，应用不会替你改系统设置，也不会反复弹窗。
详见 [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)。

### 配置 API Key

菜单栏图标 → `Open Settings…` → `DeepSeek API key` → 输入 → `Save key`。

Key 只写入本应用**自己的 Keychain 项**（service `com.atat.HoverTranslate`），
**不写** UserDefaults、源码、文档或日志。默认模型 `deepseek-flash`，可在设置里切换。

点 `Test Connection` 自检：它只发送合成文本 `Open Settings`，**不会**发送你屏幕上的任何内容。

## 使用

| 想要 | 操作 |
|---|---|
| 翻译单词 | 按住触发键（默认**右 Option**，可切左 Option），指针停在英文上 250 ms |
| 翻译整句 | 同上，同时按住 **Control** |
| 翻译选区 | 在任意应用里选中英文，按**选区快捷键**（默认 `Control-Command-T`） |
| 翻译选区内整段 | 先选中，再按住触发键把指针移到选区上停住 |
| 手动粘贴 | 菜单栏 → `Translate Selected or Pasted Text…`（打开空输入框，**不读剪贴板**） |
| 收藏 | 松键后点卡片上的 `Save` |
| 问当前语境含义 | 松键后点 `Explain` |
| 固定卡片 | `Pin`——固定后不会被新的悬停覆盖 |
| 查看 / 删除收藏 | 菜单栏 → `Saved Entries…` |

**所有应用默认可读**，不需要逐个添加。设置里的 `Applications` 是**排除列表**（默认空）：
只想让某个应用不被读取时才加进去。密码框和其它受保护控件在任何应用里都不会被读取。

## 隐私

这是本项目设计上最用力的一部分：

- 只有你**按住触发键**时才读取，不对屏幕做持续读取，也不在未触发时查询文本。
- 全局按键监视**不吞事件、不模拟按键**，左右 Option 的判定不读取按键字符内容。
- 翻译上传的**只有经过策略检查的文本**；不上传截图、完整桌面、文件路径、窗口标题或无关上下文。
- OCR 兜底**默认关闭**；开启后只截取指针下**已确认的那一个窗口**的一小块区域，一次一帧、间隔 ≥ 800 ms，
  只驻留内存，不写文件、不上传。
- 翻译缓存**只在内存**，退出即消失；不保存查询历史。
- 收藏**只保存你主动 Save 的内容**（`~/Library/Application Support/HoverTranslate/SavedEntries.json`，原子写入），
  不保存截图、窗口标题或文件路径；文件损坏时会明确报错并**保持文件原样**，不会静默清空。
- 锁屏、屏幕休眠或会话失活会取消在途请求并清空内存缓存。

## 已知限制

越是拿不准的地方，这里写得越直白——**未实测的项目不会被说成已验证**：

- **取词依赖目标应用的辅助功能支持。** 控件不支持位置映射时明确失败，不会用最近的词糊弄。
  浏览器顶部导航栏、标签栏、书签栏与系统菜单栏属于不同 AX 层级，能否取到需按页面实测。
- **OCR 兜底仍需真实环境验证。** 相关真机项（真实截屏授权后的识别、多屏摆放）在验收矩阵中仍标记为未执行。
- **VoiceOver 冲突未实测。** 整句模式使用"触发键 + Control"，而 `Control+Option` 是 VoiceOver 的默认组合键；
  本机未启用 VoiceOver，所以这条没有验证过。
- **选区快捷键的冲突检测有盲区。** 用系统公开热键接口注册，被别的应用占用会明确报出；
  但**无法检测**"用事件监视器自己监听键盘"的应用。
- **词典只对单个单词生效**，且给的是这个词常见的意思，**不判断当前语境**——语境判断交给你或 `Explain`。
  词库没有例句、音标、词形变化表。
- **悬停选区**需要目标应用提供 `AXSelectedTextRange` 与 `AXBoundsForRange`，不提供的应用会回落到普通悬停。
- 选区超过 4000 个 Unicode 字符时不发送、不截断，回落为指针处的单词。

完整的"已实测 / 未实测"清单见 [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) 与
[`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) 第 6、8 节。

## 项目结构

```
HoverTranslate/
├── App/            # 菜单栏入口、AppDelegate、菜单内容
├── Core/           # 触发策略、悬停判定、分句、缓存、请求门、协调器（纯逻辑，测试最密集）
├── Extraction/     # 辅助功能取词、选区读取、ScreenCaptureKit + Vision 的 OCR 兜底
├── Input/          # 触发键观察、选区全局快捷键注册
├── Translation/    # DeepSeek 请求构造与服务（网络可替换）
├── Dictionary/     # 离线词库查询（WordBook / WordSenseProvider）
├── Learning/       # 收藏存储与列表界面
├── Presentation/   # 浮动卡片、手动翻译窗口
├── Settings/       # 设置与 Keychain
└── Resources/      # 随包分发的词库 TSV

HoverTranslateTests/  # 301 项自动化测试
docs/                 # 设计、验收、状态、版本记录、第三方声明
tools/                # 词库生成脚本
```

设计文档（`docs/superpowers/specs/`）与开发规则（`AGENTS.md`）一并保留在仓库里——
它们是实现约束，也是这个项目为什么这样写的记录。

## 开发与测试

```bash
cd Light-Translate
xcodebuild -project HoverTranslate.xcodeproj -scheme HoverTranslate -configuration Debug \
  -destination platform=macOS -derivedDataPath "$HOME/Library/Developer/HoverTranslateDD" \
  -allowProvisioningUpdates test
```

测试全部使用假密钥与合成文本，**不依赖网络、不依赖 sleep、不进行付费 API 调用**；
计时器、网络、OCR 与时钟都通过接缝替换，因此可以离线、确定性地运行。

| 文档 | 内容 |
|---|---|
| [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) | 打开方式、权限、操作表、撤销与清理、已知限制 |
| [`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) | 功能与真机验收矩阵（区分已测 / 未测） |
| [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) | 当前状态、实测证据、跨会话续接 |
| [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md) | 每个版本的新增、修复、验证与未测项 |
| [`docs/REFERENCES.md`](docs/REFERENCES.md) | 官方技术资料与使用边界 |
| [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) | 第三方数据来源与许可 |
| [`AGENTS.md`](AGENTS.md) | 项目边界、安全与隐私规则 |

## 第三方数据

随应用分发的离线词库（`HoverTranslate/Resources/WordBook.tsv`、`WordBookLemmas.tsv`）
由 [ECDICT](https://github.com/skywind3000/ECDICT)（MIT License, Copyright (c) 2025 Linwei）生成，
收录 43342 条词条与 35171 条词形映射，再生成脚本见 `tools/build-wordbook.py`。

ECDICT 的 README 说明其数据由多个来源混合而成，**未逐项声明各来源的许可**；
再分发前请自行判断。完整说明见 [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md)。

本项目不调用任何在线词典，也不包含 Apple 系统词典的内容。

## 许可

[MIT](LICENSE) © 2026 Indium
