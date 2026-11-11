package gua

import "core:fmt"
import "core:strings"

/* 取辞：按朱熹《易学启蒙·考变占》的常用规则，由动爻数决定读哪段原文。

   0 爻动：本卦卦辞
   1 爻动：本卦该动爻爻辞
   2 爻动：本卦两动爻爻辞，以上爻为主
   3 爻动：本卦与之卦卦辞，本卦为贞、之卦为悔
   4 爻动：之卦两不变爻爻辞，以下爻为主
   5 爻动：之卦不变爻爻辞
   6 爻动：乾占用九、坤占用六；余卦占之卦卦辞 */

Source :: enum u8 { Primary, Changed }

Focus_Item :: struct {
	source: Source,
	kind:   enum u8 { Judgment, Line, Yong },
	line:   Yao, // kind == .Line 时有效
	main:   bool,
}

Reading :: struct {
	moving_count: int,
	items:        [4]Focus_Item,
	n:            int,
	rule:         string,
}

reading :: proc(g, m: Gua) -> (r: Reading) {
	cnt := card(m)
	r.moving_count = cnt
	push :: proc(r: ^Reading, it: Focus_Item) { r.items[r.n] = it; r.n += 1 }

	switch cnt {
	case 0:
		push(&r, {source = .Primary, kind = .Judgment, main = true})
		r.rule = "无动爻：占本卦卦辞"
	case 1, 2:
		top := Yao.Chu
		for y in Yao { if y in m { top = y } }
		for y in Yao { if y in m { push(&r, {source = .Primary, kind = .Line, line = y, main = y == top}) } }
		r.rule = "一爻动：占本卦动爻爻辞" if cnt == 1 else "二爻动：占本卦两动爻爻辞，以上爻为主"
	case 3:
		push(&r, {source = .Primary, kind = .Judgment, main = true})
		push(&r, {source = .Changed, kind = .Judgment})
		r.rule = "三爻动：占本卦与之卦卦辞，本卦为贞、之卦为悔"
	case 4, 5:
		still := ALL - m
		low := Yao.Shang
		for y in Yao { if y in still { low = y; break } }
		for y in Yao { if y in still { push(&r, {source = .Changed, kind = .Line, line = y, main = y == low}) } }
		r.rule = "四爻动：占之卦两不变爻爻辞，以下爻为主" if cnt == 4 else "五爻动：占之卦不变爻爻辞"
	case 6:
		if g == QIAN || g == KUN {
			push(&r, {source = .Primary, kind = .Yong, main = true})
			r.rule = "六爻皆动：乾占用九" if g == QIAN else "六爻皆动：坤占用六"
		} else {
			push(&r, {source = .Changed, kind = .Judgment, main = true})
			r.rule = "六爻皆动：占之卦卦辞"
		}
	}
	return
}

// 人读的标签，如“本卦 九三（主）”“之卦 卦辞”
focus_label :: proc(it: Focus_Item, g, m: Gua) -> string {
	src := "本卦" if it.source == .Primary else "之卦"
	h := g if it.source == .Primary else bian(g, m)
	what: string
	switch it.kind {
	case .Judgment: what = "卦辞"
	case .Yong:     what = "用九" if h == QIAN else "用六"
	case .Line:     what = line_name(it.line, it.line in h)
	}
	main := "（主）" if it.main else ""
	return fmt.tprintf("%s%s %s%s", src, NAME_ZH[number(h)], what, main)
}

focus_summary :: proc(r: Reading, g, m: Gua) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< r.n {
		if i > 0 { strings.write_string(&b, "；") }
		strings.write_string(&b, focus_label(r.items[i], g, m))
	}
	return strings.to_string(b)
}
