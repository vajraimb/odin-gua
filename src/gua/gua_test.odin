package gua

import "core:strings"
import "core:testing"

@(test)
test_self_check :: proc(t: ^testing.T) {
	ok, msg := self_check()
	testing.expect(t, ok, msg)
}

@(test)
test_known :: proc(t: ^testing.T) {
	testing.expect_value(t, number(QIAN), 1)
	testing.expect_value(t, number(KUN), 2)
	tai := Gua{.Chu, .Er, .San} // 下乾上坤
	testing.expect_value(t, number(tai), 11)
	jiji := Gua{.Chu, .San, .Wu}
	testing.expect_value(t, number(jiji), 63)
	testing.expect_value(t, number(hu(jiji)), 64)
	testing.expect_value(t, number(cuo(jiji)), 64)
	xiaochu := Gua{.Chu, .Er, .San, .Wu, .Shang}
	testing.expect_value(t, number(xiaochu), 9)
	testing.expect_value(t, number(hu(xiaochu)), 38)  // 睽
	testing.expect_value(t, number(cuo(xiaochu)), 16) // 豫
	testing.expect_value(t, number(zong(xiaochu)), 10) // 履
	testing.expect_value(t, number(bian(xiaochu, {.San, .Shang})), 60) // 节
}

@(test)
test_unicode :: proc(t: ^testing.T) {
	testing.expect_value(t, symbol_rune(1), '䷀')
	testing.expect_value(t, symbol_rune(64), '䷿')
	// 八卦符号对应 Unicode U+2630..U+2637（乾兑离震巽坎艮坤）
	want := [8]rune{0x2637, 0x2633, 0x2635, 0x2631, 0x2636, 0x2632, 0x2634, 0x2630}
	for i in 0 ..< 8 {
		rs := TRIGRAMS[i].symbol
		got: rune
		for c in rs { got = c }
		testing.expect_value(t, got, want[i])
	}
	testing.expect_value(t, NAME_EN[1], "The Creative Heaven")
	testing.expect_value(t, NAME_EN[64], "Before Completion")
}

@(test)
test_line_names :: proc(t: ^testing.T) {
	testing.expect_value(t, line_name(.Chu, true), "初九")
	testing.expect_value(t, line_name(.Er, false), "六二")
	testing.expect_value(t, line_name(.Wu, true), "九五")
	testing.expect_value(t, line_name(.Shang, false), "上六")
}

@(test)
test_seed_reproducible :: proc(t: ^testing.T) {
	a := cast_with_seed(42, .Coins)
	b := cast_with_seed(42, .Coins)
	testing.expect_value(t, a.values, b.values)
	testing.expect_value(t, a.coins, b.coins)
	for v in a.values { testing.expect(t, v >= 6 && v <= 9) }
	testing.expect_value(t, len(coins_string(a)), 18)
	for i in 0 ..< 6 {
		s := 0
		for k in 0 ..< 3 {
			f := a.coins[i][k]
			testing.expect(t, f == 2 || f == 3)
			s += int(f)
		}
		testing.expect_value(t, a.values[i], u8(s))
	}
	y := cast_with_seed(42, .Yarrow)
	testing.expect_value(t, coins_string(y), "")
	for row in y.coins {
		for f in row { testing.expect_value(t, f, 0) }
	}
}

@(test)
test_distribution :: proc(t: ^testing.T) {
	// 大样本下频率应接近理论值
	N :: 40000
	for m in Method {
		cnt: [10]int
		for s in 0 ..< N / 6 {
			c := cast_with_seed(u64(s) * 2654435761 + 1, m)
			for v in c.values { cnt[v] += 1 }
		}
		total := f64((N / 6) * 6)
		want := [4]f64{1.0 / 8, 3.0 / 8, 3.0 / 8, 1.0 / 8} if m == .Coins else [4]f64{1.0 / 16, 5.0 / 16, 7.0 / 16, 3.0 / 16}
		for k in 0 ..< 4 {
			p := f64(cnt[6 + k]) / total
			testing.expectf(t, abs(p - want[k]) < 0.015, "%v %d: %.4f vs %.4f", m, 6 + k, p, want[k])
		}
	}
}

@(test)
test_reading_rules :: proc(t: ^testing.T) {
	xiaochu := Gua{.Chu, .Er, .San, .Wu, .Shang}
	r0 := reading(xiaochu, {})
	testing.expect_value(t, focus_summary(r0, xiaochu, {}), "本卦小畜 卦辞（主）")
	m2 := Gua{.San, .Shang}
	r2 := reading(xiaochu, m2)
	testing.expect_value(t, focus_summary(r2, xiaochu, m2), "本卦小畜 九三；本卦小畜 上九（主）")
	m4 := Gua{.Chu, .Er, .San, .Si}
	r4 := reading(xiaochu, m4)
	// 之卦：初二三四变 → 阴阴阴阳阳阳 = 下坤上乾 = 否；不变爻五、上，以下（九五）为主
	testing.expect_value(t, focus_summary(r4, xiaochu, m4), "之卦否 九五（主）；之卦否 上九")
	r6 := reading(QIAN, ALL)
	testing.expect_value(t, focus_summary(r6, QIAN, ALL), "本卦乾 用九（主）")
	r6b := reading(xiaochu, ALL)
	testing.expect_value(t, focus_summary(r6b, xiaochu, ALL), "之卦豫 卦辞（主）")
}

@(test)
test_texts :: proc(t: ^testing.T) {
	hex_bits := HEX_BITS
	// 生成表里的卦画与运行时卦序一致（编译期守卫用的是 HEX_BITS，这里对上 BY_NUMBER）
	for n in 1 ..= 64 {
		bits: u8
		for y in Yao { if y in BY_NUMBER[n] { bits |= 1 << u8(y) } }
		testing.expectf(t, bits == hex_bits[n], "卦 %d 卦画不一致", n)
	}
	testing.expect_value(t, judgment_text(1), "元亨，利貞。")
	testing.expect_value(t, line_text(1, .Chu), "潛龍，勿用。")
	testing.expect(t, strings.has_prefix(judgment_text(1, .En), "Khien (represents)"))
	for n in 1 ..= 64 {
		testing.expectf(t, (yong_text(n) != "") == (n <= 2), "用九/用六 只属于乾坤：%d", n)
		testing.expect(t, judgment_text(n) != "" && judgment_text(n, .En) != "")
	}
	testing.expect_value(t, yong_text(2), "利永貞。")
	// 零拷贝：返回的切片指向编进二进制的那份经文
	s := line_text(64, .Shang)
	p, lo := uintptr(raw_data(s)), uintptr(raw_data(zh_text))
	testing.expect(t, p >= lo && p < lo + uintptr(len(zh_text)))
}
