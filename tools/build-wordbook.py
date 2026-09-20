"""Build the two wordbook files the app ships.

Source   https://github.com/skywind3000/ECDICT  (ecdict.csv)
Licence  MIT, Copyright (c) 2025 Linwei -- see docs/THIRD_PARTY_NOTICES.md
Usage    python3 tools/build-wordbook.py <path to ecdict.csv> [max glosses per part of speech]

The output files are committed because the app copies them into its bundle:
    HoverTranslate/Resources/WordBook.tsv
    HoverTranslate/Resources/WordBookLemmas.tsv

Only entries a reader of an English user interface is likely to meet are kept:
exam-syllabus words plus the 50k most frequent ones (43,342 entries today).

The inflection map is built from the csv's own `exchange` field, so it stays
inside the MIT-covered data. The repository's lemma.en.txt is NOT used: its
header allows research and educational use only.
"""
import csv, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ecdict.csv"
MAX_GLOSSES = int(sys.argv[2]) if len(sys.argv) > 2 else 3
OUT_DIR = "/tmp/wordbook"

pos_re = re.compile(r"^([a-z]{1,6}\.)\s*(.*)$")
label_re = re.compile(r"^\[([^\]]{1,6})\]\s*(.*)$")


def split_glosses(text):
    out = []
    for part in re.split(r"[,;；，、]", text):
        part = part.strip().strip("。")
        if part:
            out.append(part)
    return out


def parse(translation):
    """Ordered (pos, glosses) groups; note lines are dropped."""
    groups = []
    for raw in translation.split("\\n"):
        line = raw.strip()
        if not line:
            continue
        pos, body = "", line
        match = pos_re.match(line)
        if match:
            pos, body = match.group(1), match.group(2)
        else:
            label = label_re.match(line)
            if label:
                pos, body = "[" + label.group(1) + "]", label.group(2)
            else:
                continue
        glosses = split_glosses(body)[:MAX_GLOSSES]
        if glosses:
            groups.append((pos, glosses))
    if not groups:
        for raw in translation.split("\\n"):
            line = raw.strip()
            if line:
                groups.append(("", split_glosses(line)[:MAX_GLOSSES] or [line]))
    return groups


entries, inflections = [], {}
with open(SRC, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        tag = (row.get("tag") or "").strip()
        try:
            frq = int(row.get("frq") or 0)
        except ValueError:
            frq = 0
        translation = (row.get("translation") or "").strip()
        if not translation:
            continue
        if not (tag or 0 < frq <= 50000):
            continue
        word = row["word"].strip().lower()
        if not word or "\t" in word:
            continue
        groups = parse(translation)
        if not groups:
            continue
        fields = [word]
        for pos, glosses in groups:
            fields.append(pos)
            fields.append(";".join(g.replace("\t", " ") for g in glosses))
        entries.append("\t".join(fields))

        for part in (row.get("exchange") or "").split("/"):
            if ":" not in part:
                continue
            kind, form = part.split(":", 1)
            form = form.strip().lower()
            if kind in ("s", "p", "d", "i", "3", "r", "t") and form and form != word and "\t" not in form:
                inflections.setdefault(form, word)

import os
os.makedirs(OUT_DIR, exist_ok=True)
with open(OUT_DIR + "/WordBook.tsv", "w", encoding="utf-8") as handle:
    handle.write("\n".join(entries) + "\n")
with open(OUT_DIR + "/WordBookLemmas.tsv", "w", encoding="utf-8") as handle:
    handle.write("\n".join(f"{form}\t{lemma}" for form, lemma in sorted(inflections.items())) + "\n")

print("词条:", len(entries), "| 词形映射:", len(inflections), "| 每词性上限:", MAX_GLOSSES)
for name in ("WordBook.tsv", "WordBookLemmas.tsv"):
    size = os.path.getsize(OUT_DIR + "/" + name)
    print(f"  {name}: {size/1048576:.2f} MB")