#!/usr/bin/env python3
"""从 data/zhouyi.txt、data/legge.txt 生成 src/gua/texts_gen.odin。

生成的只是“目录”：每条经文在文件里的字节偏移与长度。经文本身由 Odin 在编译期
#load 进二进制，运行时取辞就是对这段只读内存切片，不分配、不解析。

同时生成一批 #assert，让编译器在编译期核对：
  - 文件指纹（FNV-1a 64）与生成时一致：文本改了而没重跑本脚本 → 编译失败；
  - 每卦段首的序号与卦名；
  - 每条的标签（卦辭/初九…/用九；J/1…6/U）正好落在偏移前；
  - 爻题里的“九/六”与卦象比特一致（中文），“undivided/divided”与比特一致（英文）。
用法：python3 tools/gen_texts.py"""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
ZH_PATH, EN_PATH = ROOT / "data/zhouyi.txt", ROOT / "data/legge.txt"
OUT = ROOT / "src/gua/texts_gen.odin"
REL = "../../data/"  # 相对 src/gua/

# 与 src/gua/gua.odin 的 KW 相同：KW[下卦][上卦] = 文王序号；位 0 = 初爻
KW = [[2, 16, 8, 45, 23, 35, 20, 12], [24, 51, 3, 17, 27, 21, 42, 25], [7, 40, 29, 47, 4, 64, 59, 6],
      [19, 54, 60, 58, 41, 38, 61, 10], [15, 62, 39, 31, 52, 56, 53, 33], [36, 55, 63, 49, 22, 30, 37, 13],
      [46, 32, 48, 28, 18, 50, 57, 44], [11, 34, 5, 43, 26, 14, 9, 1]]
BITS = {KW[l][u]: l | (u << 3) for l in range(8) for u in range(8)}
POS = ["初", "二", "三", "四", "五", "上"]


def fnv1a64(b: bytes) -> int:
    h = 0xcbf29ce484222325
    for x in b:
        h ^= x
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def parse(data: bytes, tags):
    """返回 hdr[n]=(段首偏移, 名字), span[n][slot]=(偏移, 长度, 标签)。"""
    hdr, span = {}, {}
    pos = 0
    for raw in data.split(b"\n"):
        line_start, pos = pos, pos + len(raw) + 1
        if not raw:
            continue
        s = raw.decode()
        m = re.match(r"^(\d\d) (.+)$", s)
        if m and int(m.group(1)) == len(hdr) + 1 and (not hdr or len(span[len(hdr)]) >= 7):
            n = int(m.group(1)); hdr[n] = (line_start, m.group(2)); span[n] = {}
            continue
        tag, _, text = s.partition(" ")
        n = len(hdr)
        slot = tags(n, tag)
        assert slot is not None and slot not in span[n], (n, tag)
        off = line_start + len(tag.encode()) + 1
        span[n][slot] = (off, len(raw) - len(tag.encode()) - 1, tag)
    assert sorted(hdr) == list(range(1, 65)), "须有 64 卦"
    for n in range(1, 65):
        want = set(range(8 if n <= 2 else 7))
        assert set(span[n]) == want, (n, sorted(span[n]))
    return hdr, span


def zh_tag(n, tag):
    if tag == "卦辭": return 0
    if tag in ("用九", "用六"): return 7
    for i, p in enumerate(POS):
        if (i in (0, 5) and tag[0] == p and tag[1] in "九六") or (i not in (0, 5) and tag[1] == p and tag[0] in "九六"):
            return i + 1
    return None


def en_tag(n, tag):
    return {"J": 0, "U": 7}.get(tag, int(tag) if tag in "123456" else None)


zh, en = ZH_PATH.read_bytes(), EN_PATH.read_bytes()
zh_hdr, zh_span = parse(zh, zh_tag)
en_hdr, en_span = parse(en, en_tag)

# 生成前先在 Python 里核对一遍，出错就不写文件（编译期断言是第二道闸）
for n in range(1, 65):
    for s in range(1, 7):
        yang = (BITS[n] >> (s - 1)) & 1
        tag = zh_span[n][s][2]
        assert (tag[1] if s in (1, 6) else tag[0]) == ("九" if yang else "六"), (n, s, tag)
        o, l, _ = en_span[n][s]
        m = re.search(r"\b(un)?divided\b", en[o:o + l].decode())
        assert m and bool(m.group(1)) == bool(yang), (n, s)

out = []
w = out.append
w("// 由 tools/gen_texts.py 从 data/zhouyi.txt、data/legge.txt 生成，请勿手改。")
w("// 改了经文就重跑：python3 tools/gen_texts.py；忘了重跑，下面的 #assert 会让编译失败。")
w("package gua\n")
w(f'ZH_FILE :: "{REL}zhouyi.txt"')
w(f'EN_FILE :: "{REL}legge.txt"')
w("ZH_TEXT :: #load(ZH_FILE, string)")
w("EN_TEXT :: #load(EN_FILE, string)")
w(f"ZH_FNV64A :: u64(0x{fnv1a64(zh):016x})")
w(f"EN_FNV64A :: u64(0x{fnv1a64(en):016x})\n")
w("// 指纹封印：文本与偏移表必须出自同一版本")
w('#assert(#load_hash(ZH_FILE, "fnv64a") == ZH_FNV64A)')
w('#assert(#load_hash(EN_FILE, "fnv64a") == EN_FNV64A)')
w(f"#assert(len(ZH_TEXT) == {len(zh)})")
w(f"#assert(len(EN_TEXT) == {len(en)})\n")

w("// 文王序 → 六位（位 0 = 初爻，1 = 阳）。与 KW 表独立书写，由单元测试互相核对。")
w("HEX_BITS :: [65]u8{0, " + ", ".join(f"0b{BITS[n]:06b}" for n in range(1, 65)) + "}\n")
w("// 繁体卦名（与经文同字形）与 Legge 1882 原书拼写")
w("NAME_TRAD :: [65]string{\"\", " + ", ".join(f'"{zh_hdr[n][1]}"' for n in range(1, 65)) + "}")
w("NAME_LEGGE :: [65]string{\"\", " + ", ".join(f'"{en_hdr[n][1]}"' for n in range(1, 65)) + "}\n")


def table(name, span):
    w(f"// {name}[卦][槽] = {{字节偏移, 长度}}；槽 0 卦辞，1–6 初爻到上爻，7 用九/用六（仅乾坤）")
    w(f"{name} :: [65][8][2]u32{{")
    w("\t{},")
    for n in range(1, 65):
        cells = ", ".join(f"{{{span[n][s][0]}, {span[n][s][1]}}}" if s in span[n] else "{0, 0}" for s in range(8))
        w(f"\t{{{cells}}}, // {n}")
    w("}\n")


table("ZH_SPAN", zh_span)
table("EN_SPAN", en_span)

w("// ---------- 编译期核对 ----------")
for n in range(1, 65):
    name = zh_hdr[n][1]
    h = zh_hdr[n][0]
    w(f"// {n} {name}")
    w(f'#assert(ZH_TEXT[{h}:{h + 3}] == "{n:02d} " && ZH_TEXT[{h + 3}:{h + 3}+len(NAME_TRAD[{n}])] == NAME_TRAD[{n}])')
    eh = en_hdr[n][0]
    w(f'#assert(EN_TEXT[{eh}:{eh + 3}] == "{n:02d} " && EN_TEXT[{eh + 3}:{eh + 3}+len(NAME_LEGGE[{n}])] == NAME_LEGGE[{n}])')
    for s in sorted(zh_span[n]):
        o = f"ZH_SPAN[{n}][{s}][0]"
        if s == 0:
            w(f'#assert(ZH_TEXT[{o}-7:{o}] == "卦辭 ")')
        elif s == 7:
            w(f'#assert(ZH_TEXT[{o}-7:{o}] == "{"用九" if n == 1 else "用六"} ")')
        else:
            # 初、上两爻位在前（初九、上六），中间四爻数在前（九二、六三）
            num_at, pos_at = (f"{o}-4", f"{o}-7") if s in (1, 6) else (f"{o}-7", f"{o}-4")
            numer = f"ZH_TEXT[{num_at}:{num_at}+3]"
            w(f'#assert(ZH_TEXT[{o}-1] == \' \' && ZH_TEXT[{pos_at}:{pos_at}+3] == "{POS[s - 1]}")')
            # 双边守卫：先确认这里确实是“九”或“六”，再与比特比较；否则偏移错位时“!= 九”也会误判为阴爻而通过
            w(f'#assert(({numer} == "九" || {numer} == "六") && (({numer} == "九") == ((HEX_BITS[{n}] >> {s - 1}) & 1 == 1)))')
    for s in sorted(en_span[n]):
        o = f"EN_SPAN[{n}][{s}][0]"
        tag = {0: "J", 7: "U"}.get(s, str(s))
        w(f'#assert(EN_TEXT[{o}-2:{o}] == "{tag} ")')
        if 1 <= s <= 6:
            off, l, _ = en_span[n][s]
            m = re.search(r"\b(un)?divided\b", en[off:off + l].decode())
            d = f"{o}+{len(en[off:off + m.start()].decode().encode())}"
            w(f'#assert((EN_TEXT[{d}:{d}+9] == "undivided" || EN_TEXT[{d}:{d}+7] == "divided") && ((EN_TEXT[{d}:{d}+9] == "undivided") == ((HEX_BITS[{n}] >> {s - 1}) & 1 == 1)))')

OUT.write_text("\n".join(out) + "\n")
print("wrote", OUT.relative_to(ROOT), f"zh {len(zh)} B  en {len(en)} B  fnv64a zh={fnv1a64(zh):016x} en={fnv1a64(en):016x}")
