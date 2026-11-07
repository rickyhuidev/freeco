# Third-party data

## CC-CEDICT

`ChineseOCR/Assets.xcassets/cedict.dataset/cedict.tsv` is derived from
[CC-CEDICT](https://cc-cedict.org/wiki/), published by MDBG, based on CEDICT
© 1997, 1998 Paul Andrew Denisowski.

It is licensed under the
[Creative Commons Attribution-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-sa/4.0/).
That file (and only that file) is distributed under the same license.

Modification: comment lines were removed and each entry was reformatted from
`TRAD SIMP [pinyin] /defs/` into tab-separated columns
`simplified, traditional, pinyin, definitions` by
`build_tools/preprocess_cedict.py`. Entry content is unchanged. The
attribution is also shown in the app (the ⓘ button on the camera screen).

To refresh the data, download
`https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz`,
gunzip it to `build_tools/cedict.txt`, and run
`python3 build_tools/preprocess_cedict.py` from the repo root.
