package gua

import "core:math/rand"

Method :: enum u8 {
	Coins,  // 三钱法：6 老阴 1/8，7 少阳 3/8，8 少阴 3/8，9 老阳 1/8
	Yarrow, // 大衍筮法的概率：6 1/16，7 5/16，8 7/16，9 3/16
}

METHOD_NAME := [Method]string{
	.Coins  = "coins",
	.Yarrow = "yarrow",
}

// 一次起卦：六爻的 6/7/8/9，自初爻到上爻
Cast :: struct {
	values: [6]u8,
	method: Method,
	seed:   u64,
}

// 同一 seed + method 必得同一卦，便于复现与审计
cast_with_seed :: proc(seed: u64, method: Method) -> (c: Cast) {
	state := rand.create(seed)
	gen := rand.default_random_generator(&state)
	c.seed = seed
	c.method = method
	for i in 0 ..< 6 {
		switch method {
		case .Coins:
			s := 0
			for _ in 0 ..< 3 { s += 3 if rand.int_max(2, gen) == 1 else 2 }
			c.values[i] = u8(s)
		case .Yarrow:
			r := rand.int_max(16, gen)
			switch {
			case r < 1:  c.values[i] = 6
			case r < 6:  c.values[i] = 7
			case r < 13: c.values[i] = 8
			case:        c.values[i] = 9
			}
		}
	}
	return
}

primary :: proc(c: Cast) -> (g: Gua) { // 本卦：7、9 为阳
	for v, i in c.values { if v == 7 || v == 9 { g += {Yao(i)} } }
	return
}

moving :: proc(c: Cast) -> (m: Gua) { // 动爻：6、9
	for v, i in c.values { if v == 6 || v == 9 { m += {Yao(i)} } }
	return
}

values_string :: proc(c: Cast) -> string {
	b: [6]u8
	for v, i in c.values { b[i] = '0' + v }
	return string_clone_temp(b[:])
}

@(private)
string_clone_temp :: proc(b: []u8) -> string {
	out := make([]u8, len(b), context.temp_allocator)
	copy(out, b)
	return string(out)
}
