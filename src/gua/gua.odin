/* gua — 卦的表示与变化。

   一爻一位：位为 1 = 阳爻，0 = 阴爻；初爻在最低位（bit 0），上爻在 bit 5。
   下卦 = 低三位，上卦 = 高三位。 */
package gua

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

Yao :: enum u8 { Chu, Er, San, Si, Wu, Shang } // 初 二 三 四 五 上
Gua :: bit_set[Yao; u8]

#assert(size_of(Gua) == 1)

ALL :: Gua{.Chu, .Er, .San, .Si, .Wu, .Shang}
QIAN :: ALL
KUN :: Gua{}

bits :: proc(g: Gua) -> u8 { return transmute(u8)g }
from_bits :: proc(b: u8) -> Gua { return transmute(Gua)(b & 0x3f) }
lower :: proc(g: Gua) -> u8 { return bits(g) & 7 }
upper :: proc(g: Gua) -> u8 { return bits(g) >> 3 }

// ---------- 八卦（按三位编码索引，自下而上） ----------

Trigram :: struct {
	zh, symbol, en, nature, pinyin: string,
}

// 编码：坤000 震001 坎010 兑011 艮100 离101 巽110 乾111
TRIGRAMS := [8]Trigram{
	{"坤", "☷", "Earth", "地", "Kun"},
	{"震", "☳", "Thunder", "雷", "Zhen"},
	{"坎", "☵", "Water", "水", "Kan"},
	{"兑", "☱", "Lake", "泽", "Dui"},
	{"艮", "☶", "Mountain", "山", "Gen"},
	{"离", "☲", "Fire", "火", "Li"},
	{"巽", "☴", "Wind", "风", "Xun"},
	{"乾", "☰", "Heaven", "天", "Qian"},
}

// ---------- 文王序 ----------

// KW[下卦][上卦] = 文王序号
KW := [8][8]u8{
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

NAME_ZH := [65]string{"",
	"乾", "坤", "屯", "蒙", "需", "讼", "师", "比", "小畜", "履", "泰", "否", "同人", "大有", "谦", "豫",
	"随", "蛊", "临", "观", "噬嗑", "贲", "剥", "复", "无妄", "大畜", "颐", "大过", "坎", "离", "咸", "恒",
	"遯", "大壮", "晋", "明夷", "家人", "睽", "蹇", "解", "损", "益", "夬", "姤", "萃", "升", "困", "井",
	"革", "鼎", "震", "艮", "渐", "归妹", "丰", "旅", "巽", "兑", "涣", "节", "中孚", "小过", "既济", "未济",
}

PINYIN := [65]string{"",
	"Qian", "Kun", "Zhun", "Meng", "Xu", "Song", "Shi", "Bi", "Xiao Chu", "Lü", "Tai", "Pi", "Tong Ren", "Da You", "Qian", "Yu",
	"Sui", "Gu", "Lin", "Guan", "Shi He", "Bi", "Bo", "Fu", "Wu Wang", "Da Chu", "Yi", "Da Guo", "Kan", "Li", "Xian", "Heng",
	"Dun", "Da Zhuang", "Jin", "Ming Yi", "Jia Ren", "Kui", "Jian", "Xie", "Sun", "Yi", "Guai", "Gou", "Cui", "Sheng", "Kun", "Jing",
	"Ge", "Ding", "Zhen", "Gen", "Jian", "Gui Mei", "Feng", "Lü", "Xun", "Dui", "Huan", "Jie", "Zhong Fu", "Xiao Guo", "Ji Ji", "Wei Ji",
}

// 文王序号 → 卦（启动时由 KW 反推）
BY_NUMBER: [65]Gua

@(init)
init_tables :: proc "contextless" () {
	for i in 0 ..< 64 {
		g := transmute(Gua)u8(i)
		BY_NUMBER[KW[i & 7][i >> 3]] = g
	}
}

number :: proc(g: Gua) -> int { return int(KW[lower(g)][upper(g)]) }

// Unicode 卦符：U+4DC0 起按文王序排列
symbol_rune :: proc(n: int) -> rune { return rune(0x4DC0 + n - 1) }

symbol :: proc(n: int, allocator := context.temp_allocator) -> string {
	buf, w := utf8.encode_rune(symbol_rune(n))
	return strings.clone(string(buf[:w]), allocator)
}

// 自下而上的六位串，如乾 "111111"、泰 "111000"
binary_string :: proc(g: Gua, allocator := context.temp_allocator) -> string {
	b: [6]u8
	for y in Yao { b[int(y)] = '1' if y in g else '0' }
	return strings.clone(string(b[:]), allocator)
}

// ---------- 变化 ----------

cuo :: proc(g: Gua) -> Gua { return ALL - g } // 错卦：六爻全反

zong :: proc(g: Gua) -> Gua { // 综卦：上下颠倒
	r: Gua
	for y in Yao { if y in g { r += {Yao(5 - u8(y))} } }
	return r
}

hu :: proc(g: Gua) -> Gua { // 互卦：二三四爻作下卦，三四五爻作上卦
	b := bits(g)
	return from_bits(((b >> 1) & 7) | (((b >> 2) & 7) << 3))
}

bian :: proc(g, moving: Gua) -> Gua { return g ~ moving } // 之卦

// ---------- 爻名 ----------

POS_ZH := [6]string{"初", "二", "三", "四", "五", "上"}

// 初九 / 六二 / 上六 ……
line_name :: proc(y: Yao, yang: bool, allocator := context.temp_allocator) -> string {
	num := "九" if yang else "六"
	switch y {
	case .Chu:   return fmt.aprintf("初%s", num, allocator = allocator)
	case .Shang: return fmt.aprintf("上%s", num, allocator = allocator)
	case .Er, .San, .Si, .Wu:
	}
	return fmt.aprintf("%s%s", num, POS_ZH[int(y)], allocator = allocator)
}

// ---------- 自检 ----------

// 64 卦齐全；文王序两两成对，后一卦为前一卦之综卦，上下对称者为错卦。
self_check :: proc() -> (ok: bool, msg: string) {
	seen: [65]bool
	for i in 0 ..< 64 {
		g := transmute(Gua)u8(i)
		n := number(g)
		if n < 1 || n > 64 { return false, fmt.tprintf("序号越界: %d", n) }
		if seen[n] { return false, fmt.tprintf("重复序号: %d", n) }
		seen[n] = true
		if BY_NUMBER[n] != g { return false, fmt.tprintf("反查失败: %d", n) }
		pair := n + 1 if n % 2 == 1 else n - 1
		z := zong(g)
		want := cuo(g) if z == g else z
		if number(want) != pair { return false, fmt.tprintf("文王配对不符: %d", n) }
	}
	if NAME_ZH[1] != "乾" || NAME_ZH[64] != "未济" { return false, "卦名表错位" }
	return true, ""
}
