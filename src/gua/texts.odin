package gua

import "core:fmt"

/* 经文：卦辞、爻辞、用九/用六，中文（通行本，繁体）与 Legge 1882 英译。

   文本由 texts_gen.odin 里的 #load 在编译期嵌入二进制，偏移表也是编译期常量；
   运行时取一条经文就是对只读内存切一刀，不分配、不解析、不读文件。
   来源与逐条出处见 data/SOURCES.md、data/provenance.tsv。 */

Lang :: enum u8 { Zh, En }

Slot :: enum u8 { Judgment = 0, L1, L2, L3, L4, L5, L6, Yong }

// 运行时可切片的副本：常量字符串只能用常量下标切，赋给变量后才能用变量下标
@(private) zh_text := ZH_TEXT
@(private) en_text := EN_TEXT
@(private) zh_span := ZH_SPAN
@(private) en_span := EN_SPAN

// 繁体卦名与 Legge 拼写（运行时可按变量索引）
name_trad := NAME_TRAD
name_legge := NAME_LEGGE

// n 卦某一槽的原文；不存在（如非乾坤的用九/用六、越界）时返回 ""
text :: proc(n: int, slot: Slot, lang := Lang.Zh) -> string {
	if n < 1 || n > 64 { return "" }
	sp := zh_span[n][slot] if lang == .Zh else en_span[n][slot]
	if sp[1] == 0 { return "" }
	t := zh_text if lang == .Zh else en_text
	return t[sp[0]:][:sp[1]]
}

judgment_text :: proc(n: int, lang := Lang.Zh) -> string { return text(n, .Judgment, lang) }
line_text :: proc(n: int, y: Yao, lang := Lang.Zh) -> string { return text(n, Slot(u8(y) + 1), lang) }
yong_text :: proc(n: int, lang := Lang.Zh) -> string { return text(n, .Yong, lang) }

// 取辞项对应的原文
focus_text :: proc(it: Focus_Item, g, m: Gua, lang := Lang.Zh) -> string {
	h := g if it.source == .Primary else bian(g, m)
	n := number(h)
	switch it.kind {
	case .Judgment: return judgment_text(n, lang)
	case .Line:     return line_text(n, it.line, lang)
	case .Yong:     return yong_text(n, lang)
	}
	return ""
}

// 文本指纹，写进日志与 --version，复盘时可知当时用的是哪一版经文
texts_id :: proc() -> string {
	return fmt.tprintf("zh:%016x en:%016x", ZH_FNV64A, EN_FNV64A)
}
