package gua

import "core:fmt"
import "core:strings"

// 一行标题：䷈ 第9卦 小畜 Xiao Chu · Small Taming（上巽☴ 下乾☰）
title :: proc(g: Gua) -> string {
	n := number(g)
	u, l := TRIGRAMS[upper(g)], TRIGRAMS[lower(g)]
	return fmt.tprintf("%s 第%d卦 %s %s · %s（上%s%s 下%s%s）",
		symbol(n), n, NAME_ZH[n], PINYIN[n], NAME_EN[n], u.zh, u.symbol, l.zh, l.symbol)
}

/* 六爻图，自上而下。老阳标 ○，老阴标 ×（传统记法）。
   values 为 nil 时只画阴阳。 */
draw :: proc(g: Gua, values: []u8 = nil) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i := 5; i >= 0; i -= 1 {
		y := Yao(i)
		yang := y in g
		bar := "━━━━━━━" if yang else "━━━ ━━━"
		strings.write_string(&b, fmt.tprintf("  %s  %s", line_name(y, yang), bar))
		if values != nil {
			switch values[i] {
			case 9: strings.write_string(&b, "  ○ 老阳·动")
			case 6: strings.write_string(&b, "  × 老阴·动")
			}
		}
		if i > 0 { strings.write_byte(&b, '\n') }
	}
	return strings.to_string(b)
}
