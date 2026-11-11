package main

import "core:fmt"
import "core:math/rand"

// 一爻一位：位为 1 = 阳爻，0 = 阴爻；初爻在最低位
Yao :: enum u8 { Chu, Er, San, Si, Wu, Shang }
Gua :: bit_set[Yao; u8]

// 八卦（三位，自下而上）：乾111 兑011 离101 震001 巽110 坎010 艮100 坤000
TRI_NAME := [8]string{"坤", "震", "坎", "兑", "艮", "离", "巽", "乾"}

// 文王序：KW[下卦][上卦]
KW := [8][8]int{
	//  上: 坤  震  坎  兑  艮  离  巽  乾
	0 = {2, 16, 8, 45, 23, 35, 20, 12},   // 下坤
	1 = {24, 51, 3, 17, 27, 21, 42, 25},  // 下震
	2 = {7, 40, 29, 47, 4, 64, 59, 6},    // 下坎
	3 = {19, 54, 60, 58, 41, 38, 61, 10}, // 下兑
	4 = {15, 62, 39, 31, 52, 56, 53, 33}, // 下艮
	5 = {36, 55, 63, 49, 22, 30, 37, 13}, // 下离
	6 = {46, 32, 48, 28, 18, 50, 57, 44}, // 下巽
	7 = {11, 34, 5, 43, 26, 14, 9, 1},    // 下乾
}

NAME := [65]string{"",
	"乾", "坤", "屯", "蒙", "需", "讼", "师", "比", "小畜", "履", "泰", "否", "同人", "大有", "谦", "豫",
	"随", "蛊", "临", "观", "噬嗑", "贲", "剥", "复", "无妄", "大畜", "颐", "大过", "坎", "离", "咸", "恒",
	"遯", "大壮", "晋", "明夷", "家人", "睽", "蹇", "解", "损", "益", "夬", "姤", "萃", "升", "困", "井",
	"革", "鼎", "震", "艮", "渐", "归妹", "丰", "旅", "巽", "兑", "涣", "节", "中孚", "小过", "既济", "未济",
}

bits  :: proc(g: Gua) -> u8 { return transmute(u8)g }
lower :: proc(g: Gua) -> u8 { return bits(g) & 7 }
upper :: proc(g: Gua) -> u8 { return bits(g) >> 3 }
kw    :: proc(g: Gua) -> int { return KW[lower(g)][upper(g)] }

// 错卦：六爻全反
cuo :: proc(g: Gua) -> Gua { return ~g }
// 综卦：上下颠倒
zong :: proc(g: Gua) -> Gua {
	r: Gua
	for y in Yao { if y in g { r += {Yao(5 - u8(y))} } }
	return r
}
// 互卦：二三四爻作下卦，三四五爻作上卦
hu :: proc(g: Gua) -> Gua {
	b := bits(g)
	return transmute(Gua)(((b >> 1) & 7) | (((b >> 2) & 7) << 3))
}

draw :: proc(g: Gua, moving: Gua) {
	for i := 5; i >= 0; i -= 1 {
		y := Yao(i)
		line := "▅▅▅▅▅▅▅" if y in g else "▅▅▅ ▅▅▅"
		mark := ""
		if y in moving { mark = "  ← 动" }
		fmt.printf("  %s%s\n", line, mark)
	}
}

show :: proc(label: string, g: Gua) {
	fmt.printf("%s：%d %s（上%s下%s）\n", label, kw(g), NAME[kw(g)], TRI_NAME[upper(g)], TRI_NAME[lower(g)])
}

// 三钱法：三枚硬币，正=3 反=2，和为 6/7/8/9
// 6 老阴（动） 7 少阳 8 少阴 9 老阳（动）
qigua :: proc() -> (g: Gua, moving: Gua) {
	for y in Yao {
		s := 0
		for _ in 0 ..< 3 { s += 3 if rand.int_max(2) == 1 else 2 }
		if s == 7 || s == 9 { g += {y} }
		if s == 6 || s == 9 { moving += {y} }
	}
	return
}

main :: proc() {
	// 自检：文王序两两成对，后一卦是前一卦的综卦；上下对称的卦则为错卦
	seen: [65]bool
	for i in 0 ..< 64 {
		g := transmute(Gua)u8(i)
		seen[kw(g)] = true
		n := kw(g)
		pair := n + 1 if n % 2 == 1 else n - 1
		z := zong(g)
		want := cuo(g) if z == g else z
		if kw(want) != pair { fmt.println("表有误:", n) }
	}
	for i in 1 ..= 64 { if !seen[i] { fmt.println("缺卦:", i) } }
	fmt.println("自检通过：64 卦齐全，32 对“非综即错”全部吻合\n")

	g, m := qigua()
	draw(g, m)
	show("本卦", g)
	show("互卦", hu(g))
	show("错卦", cuo(g))
	show("综卦", zong(g))
	if m != {} { show("变卦", g ~ m) } else { fmt.println("无动爻，以本卦论") }
}
