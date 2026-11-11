package main

import "core:fmt"

Yao :: enum u8 { Chu, Er, San, Si, Wu, Shang }
Gua :: bit_set[Yao; u8]

// 卦即类型：Hex({...}) 每个不同的卦都是不同的类型
Hex :: struct($G: Gua) {}

QIAN   :: Gua{.Chu, .Er, .San, .Si, .Wu, .Shang}
KUN    :: Gua{}
JIJI   :: Gua{.Chu, .San, .Wu}   // 既济：阳在一三五
WEIJI  :: Gua{.Er, .Si, .Shang}  // 未济

// 变：输入一个卦类型 + 动爻，返回值的“类型”在编译期算出
bian :: proc($G: Gua, $M: Gua) -> Hex(G ~ M) { return {} }

// 当位：阳居一三五、阴居二四六
dangwei :: proc($G: Gua) -> bool { return G == JIJI }

// 只有九五（第五爻为阳）的卦才能调用“君位”
junwei :: proc(h: Hex($G)) where (.Wu in G) { fmt.println("  九五：飞龙在天") }

// 编译期写死的一卦：由 -define:GUA=N 决定
GUA :: transmute(Gua)u8(#config(GUA, 21))

when GUA == JIJI {
	verdict :: proc() -> string { return "既济：亨小，利贞" }
} else when GUA == QIAN {
	verdict :: proc() -> string { return "乾：元亨利贞" }
} else {
	verdict :: proc() -> string { return "此卦未收录解读" }
}

main :: proc() {
	a: Hex(QIAN)
	b := bian(QIAN, Gua{.Chu, .Er, .San, .Si, .Wu, .Shang})  // 六爻全变
	fmt.println("乾全变 → 类型:", typeid_of(type_of(b)) == typeid_of(Hex(KUN)) ? "Hex(坤)" : "?")

	c := bian(JIJI, Gua{.Chu, .Er, .San, .Si, .Wu, .Shang})
	fmt.println("既济全变 → 类型:", typeid_of(type_of(c)) == typeid_of(Hex(WEIJI)) ? "Hex(未济)" : "?")

	#assert(JIJI ~ QIAN == WEIJI)  // 编译期断言：既济的错卦是未济

	junwei(a)          // 乾有九五，可以调用
	fmt.println("编译时定下的卦 GUA =", u8(transmute(u8)GUA), "→", verdict())
	when #config(TRY_KUN, false) { junwei(Hex(KUN){}) }  // 坤没有九五
}
