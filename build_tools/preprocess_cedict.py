#!/usr/bin/env python3
"""Convert raw CC-CEDICT into a compact TSV bundled with the app.

Output line format (UTF-8, one entry per line):
    simplified <TAB> traditional <TAB> numberedPinyin <TAB> def1/def2/...

Comment lines (starting with #) are dropped. The runtime parser only has to
split on tabs, which is far faster than parsing the original bracket/slash
format for ~125k entries at launch.
"""
import re
import sys

SRC = "build_tools/cedict.txt"
DST = "ChineseOCR/Assets.xcassets/cedict.dataset/cedict.tsv"

line_re = re.compile(r"^(\S+)\s+(\S+)\s+\[([^\]]*)\]\s+/(.*)/\s*$")

def main():
    kept = 0
    skipped = 0
    with open(SRC, "r", encoding="utf-8") as f, open(DST, "w", encoding="utf-8") as out:
        for line in f:
            if not line or line.startswith("#"):
                continue
            m = line_re.match(line.rstrip("\n"))
            if not m:
                skipped += 1
                continue
            trad, simp, pinyin, defs = m.groups()
            # defs already slash-separated; collapse internal tabs just in case
            defs = defs.replace("\t", " ")
            out.write(f"{simp}\t{trad}\t{pinyin}\t{defs}\n")
            kept += 1
    print(f"kept={kept} skipped={skipped}")

if __name__ == "__main__":
    main()
