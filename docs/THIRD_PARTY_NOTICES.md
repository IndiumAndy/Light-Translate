# 第三方数据与许可

本应用默认在设备端工作，只随包分发一份词典数据文件。

## ECDICT（英汉词典数据）

- **用途**：`HoverTranslate/Resources/WordBook.tsv`（词性与多个中文释义）与 `WordBookLemmas.tsv`（变形 → 原型）。
- **来源**：<https://github.com/skywind3000/ECDICT> 的 `ecdict.csv`（2026-09-18 取得）。
- **许可**：该仓库的 `LICENSE` 为 **MIT License**，Copyright (c) 2025 Linwei。本应用按 MIT 条款使用并在此署名。
- **再生成**：`python3 tools/build-wordbook.py <ecdict.csv 路径> 3`。生成脚本保留在仓库里，输出文件一并提交，因为应用直接随包分发这两个文件。
- **收录范围**：考试大纲词汇 ∪ 当代语料库词频 ≤ 50000，共 **43342 条**；词形映射 35171 条。体积 2.03 MB + 0.59 MB。
- **已知限制（如实记录）**：ECDICT 的 README 说明了混合数据来源（EDictAZ.txt、各类考纲词表、`cdict-1.0-1.rpm`、BNC、NodeBox/WordNet），**没有逐项声明各来源的许可**。上游仓库自身以 MIT 发布，本仓库因此按 MIT 署名并保留了再生成脚本；
  但若你要**再分发**本仓库或其中的词典文件，请自行确认上游各来源的许可，或改用 `tools/build-wordbook.py` 自行生成。
- **未使用**：该仓库的 `lemma.en.txt`。其文件头写明 "free to use for any research and/or educational purposes"，属于仅研究/教育用途，不适合随应用分发。词形映射改由 `ecdict.csv` 自带的 `exchange` 字段离线生成，完全落在 MIT 覆盖的数据内。

## 没有使用的第三方内容

- 不调用任何在线词典、翻译网页或未授权接口。
- 不包含 Apple 系统词典的内容（系统词典只在设备上由系统自己管理，本应用不读取、不复制）。
