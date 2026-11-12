package journal

// 卦例：把日志里同一 id 的几行（cast / annotation / review）合成一条。
// 日志只追加；这里读全量、按 id 归并。个人日志一年不过几百行，全量读足够快。

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:time"
import "core:unicode"

Case :: struct {
	entry:    json.Object, // cast 行
	note:     json.Object, // annotation，无则为 nil
	reviewed: bool,        // 第 4 步的 review 记录
}

// 全部卦例，按起卦先后排列；index: id -> 下标
load_cases :: proc() -> (cases: [dynamic]Case, index: map[string]int) {
	cases = make([dynamic]Case, context.temp_allocator)
	index = make(map[string]int, context.temp_allocator)
	data, err := os.read_entire_file_from_path(path(), context.temp_allocator)
	if err != nil { return }
	for l in strings.split_lines(string(data), context.temp_allocator) {
		line := strings.trim_space(l)
		if line == "" { continue }
		v, perr := json.parse_string(line, parse_integers = true, allocator = context.temp_allocator)
		if perr != nil { continue }
		o, ok := v.(json.Object)
		if !ok { continue }
		kind, _ := o["kind"].(json.String)
		switch kind {
		case "cast":
			id, _ := o["id"].(json.String)
			index[id] = len(cases)
			append(&cases, Case{entry = o})
		case "annotation", "review":
			id, _ := o["cast_id"].(json.String)
			i, found := index[id]
			if !found { continue }
			if kind == "annotation" {
				if cases[i].note == nil { cases[i].note = o } // 只认第一条：预测落笔不改
			} else {
				cases[i].reviewed = true
			}
		}
	}
	return
}

str :: proc(o: json.Object, k: string) -> string {
	s, _ := o[k].(json.String)
	return s
}

// 已到复盘日、尚未复盘的卦例（新的在前）
due :: proc(cases: []Case, today: string) -> []Case {
	out := make([dynamic]Case, context.temp_allocator)
	#reverse for c in cases {
		if c.note == nil || c.reviewed { continue }
		if d := str(c.note, "review_after"); d != "" && d <= today { append(&out, c) }
	}
	return out[:]
}

// ---------- 日期 ----------

today :: proc() -> string {
	s := now_string()
	return s[:10] if len(s) >= 10 else ""
}

// 今天之后第 n 天（当地日期）
date_after_days :: proc(n: int) -> string {
	t := time.time_add(time.now(), time.Duration(n) * 24 * time.Hour)
	off := local_offset_minutes(t)
	s, ok := time.time_to_rfc3339(time.time_add(t, time.Duration(off) * time.Minute), off, false, context.temp_allocator)
	return s[:10] if ok && len(s) >= 10 else ""
}

valid_date :: proc(s: string) -> bool {
	if len(s) != 10 || s[4] != '-' || s[7] != '-' { return false }
	_, n := time.rfc3339_to_time_utc(strings.concatenate({s, "T00:00:00Z"}, context.temp_allocator))
	return n > 0
}

// 距 ts（RFC3339）过去了多少小时；解析失败返回很大的数
hours_since :: proc(ts: string) -> f64 {
	t, n := time.rfc3339_to_time_utc(ts)
	if n == 0 { return 1e9 }
	return time.duration_hours(time.diff(t, time.now()))
}

// ---------- 问题相似度（防重摇） ----------

// 去掉空白与标点、转小写
normalize_question :: proc(s: string) -> []rune {
	out := make([dynamic]rune, context.temp_allocator)
	for r in s {
		if unicode.is_space(r) || unicode.is_punct(r) || is_cjk_punct(r) { continue }
		append(&out, unicode.to_lower(r))
	}
	return out[:]
}

@(private)
is_cjk_punct :: proc(r: rune) -> bool {
	switch r {
	case '，', '。', '？', '！', '、', '；', '：', '“', '”', '‘', '’', '（', '）', '《', '》', '「', '」', '…', '—', '·':
		return true
	}
	return false
}

// 字二元组 Dice 系数，0..1；完全相同为 1
similarity :: proc(a, b: string) -> f64 {
	x, y := normalize_question(a), normalize_question(b)
	if len(x) == 0 || len(y) == 0 { return 0 }
	if slice_eq(x, y) { return 1 }
	if len(x) < 2 || len(y) < 2 { return 0 }
	grams := make(map[[2]rune]int, context.temp_allocator)
	for i in 0 ..< len(x) - 1 { grams[{x[i], x[i + 1]}] += 1 }
	common := 0
	for i in 0 ..< len(y) - 1 {
		k := [2]rune{y[i], y[i + 1]}
		if grams[k] > 0 { grams[k] -= 1; common += 1 }
	}
	return 2 * f64(common) / f64(len(x) - 1 + len(y) - 1)
}

@(private)
slice_eq :: proc(a, b: []rune) -> bool {
	if len(a) != len(b) { return false }
	for r, i in a { if b[i] != r { return false } }
	return true
}

