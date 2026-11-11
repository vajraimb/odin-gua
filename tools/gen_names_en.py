#!/usr/bin/env python3
"""从 Unicode 字符名生成 64 卦英文名表 → src/gua/names_en.odin
用法：python3 tools/gen_names_en.py"""
import unicodedata as u, pathlib
small = {"of", "the", "in", "at", "and", "for", "to", "with", "a", "on"}
rows = []
for n in range(64):
    nm = u.name(chr(0x4DC0 + n)).removeprefix("HEXAGRAM FOR ")
    w = nm.lower().split()
    t = " ".join(x if (i > 0 and x in small) else x.capitalize() for i, x in enumerate(w))
    rows.append(f'\t"{t}", // {n + 1} U+{0x4DC0 + n:04X}')
src = (
    "// 由 tools/gen_names_en.py 从 Unicode 字符名生成，请勿手改。\n"
    "package gua\n\n"
    "NAME_EN := [65]string{\n\t\"\",\n" + "\n".join(rows) + "\n}\n"
)
p = pathlib.Path(__file__).resolve().parent.parent / "src/gua/names_en.odin"
p.write_text(src)
print("wrote", p)
