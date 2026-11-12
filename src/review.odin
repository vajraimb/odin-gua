package main

// 第 3 步：annotate（写下模型解读）、复盘提醒、防重摇（不再三）。
// 规则都在服务器里执行，不靠模型自觉：
// - 同一卦只收第一条解读，写下后不能改（否则复盘时可以事后修改预测）。
// - 同一问题在窗口期内不重摇；确需重起要显式 recast + reason，新卦记为“渎”，不计入统计。

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "gua"
import "journal"
import "mcp"

DEFAULT_RECAST_HOURS :: 72
SIMILAR :: 0.7 // 问题相似度阈值（字二元组 Dice）
DEFAULT_REVIEW_DAYS :: 14

STANCES :: []string{"favorable", "unfavorable", "mixed", "unclear"}
stance_zh :: proc(s: string) -> string {
	switch s {
	case "favorable":   return "偏吉"
	case "unfavorable": return "偏凶"
	case "mixed":       return "吉凶参半"
	case "unclear":     return "不明"
	}
	return s
}

recast_hours :: proc() -> f64 {
	if s := os.get_env("GUA_RECAST_HOURS", context.temp_allocator); s != "" {
		if v, ok := strconv.parse_f64(s); ok && v >= 0 { return v }
	}
	return DEFAULT_RECAST_HOURS
}

// 窗口期内问过的相似问题（不计已标记为渎的卦，取最近一条）
find_recent_same :: proc(cases: []journal.Case, question: string) -> (prev: journal.Case, found: bool) {
	win := recast_hours()
	#reverse for c in cases {
		if journal.hours_since(journal.str(c.entry, "ts")) > win { break }
		if du, _ := c.entry["du"].(json.Boolean); du { continue }
		if journal.similarity(journal.str(c.entry, "question"), question) >= SIMILAR { return c, true }
	}
	return
}

case_title :: proc(o: json.Object) -> string {
	p, _ := o["primary"].(json.Integer)
	pn := clamp(int(p), 1, 64)
	s := fmt.tprintf("%s %s", gua.symbol(pn), gua.NAME_ZH[pn])
	if ch, has := o["changed"].(json.Integer); has {
		cn := clamp(int(ch), 1, 64)
		s = fmt.tprintf("%s 之 %s %s", s, gua.symbol(cn), gua.NAME_ZH[cn])
	}
	return s
}

// 卦例当前状态：待解读 / 待复盘 YYYY-MM-DD / 已到复盘日 / 已复盘 / 渎
case_status :: proc(c: journal.Case, today: string) -> string {
	if du, _ := c.entry["du"].(json.Boolean); du { return "渎（不计统计）" }
	if c.reviewed { return "已复盘" }
	if c.note == nil { return "待解读" }
	d := journal.str(c.note, "review_after")
	if d <= today { return fmt.tprintf("已到复盘日（%s）", d) }
	return fmt.tprintf("待复盘 %s", d)
}

due_json :: proc(due: []journal.Case) -> string {
	items := make([dynamic]string, context.temp_allocator)
	for c in due {
		append(&items, obj(
			{"id", q(journal.str(c.entry, "id"))},
			{"question", q(journal.str(c.entry, "question"))},
			{"review_after", q(journal.str(c.note, "review_after"))},
			{"prediction", q(journal.str(c.note, "prediction"))},
		))
	}
	return arr(items[:])
}

write_due :: proc(b: ^strings.Builder, due: []journal.Case) {
	if len(due) == 0 { return }
	fmt.sbprintf(b, "\n\n复盘提醒：%d 卦已到复盘日，请顺便问用户结果如何：", len(due))
	for c in due {
		fmt.sbprintf(b, "\n  · %s（%s）问：%s\n    当时预测：%s", journal.str(c.entry, "id"), journal.str(c.note, "review_after"), journal.str(c.entry, "question"), journal.str(c.note, "prediction"))
	}
}

number_arg :: proc(c: ^mcp.Call, k: string) -> (f64, bool) {
	#partial switch v in c.args[k] {
	case json.Float:   return f64(v), true
	case json.Integer: return f64(v), true
	}
	return 0, false
}

tool_annotate :: proc(c: ^mcp.Call) -> mcp.Tool_Result {
	id := strings.trim_space(str_arg(c, "id"))
	if id == "" { return fail("annotate 需要 id（cast 返回的卦例 id，如 g20261112-3fa9c2）") }
	cases, index := journal.load_cases()
	i, found := index[id]
	if !found { return fail(fmt.tprintf("日志里没有卦例 %s", id)) }
	cs := cases[i]
	if cs.note != nil {
		return fail(fmt.tprintf("%s 已于 %s 写过解读，落笔不改（复盘才有意义）。当时的预测：%s", id, journal.str(cs.note, "ts"), journal.str(cs.note, "prediction")))
	}

	stance := str_arg(c, "stance")
	ok_stance := false
	for s in STANCES { if s == stance { ok_stance = true } }
	if !ok_stance { return fail("stance 只能是 favorable / unfavorable / mixed / unclear") }
	conf, has_conf := number_arg(c, "confidence")
	if !has_conf || conf < 0 || conf > 1 { return fail("confidence 必须是 0 到 1 之间的数（模型对这个倾向的把握）") }
	prediction := strings.trim_space(str_arg(c, "prediction"))
	if prediction == "" { return fail("prediction 必填：写一句将来能对照结果检验的具体判断，例如“两周内对方会让步，但价格不到预期”") }
	summary := strings.trim_space(str_arg(c, "summary"))

	today := journal.today()
	review_after := strings.trim_space(str_arg(c, "review_after"))
	if review_after == "" {
		days := DEFAULT_REVIEW_DAYS
		if d, ok := number_arg(c, "review_in_days"); ok { days = clamp(int(d), 1, 3650) }
		review_after = journal.date_after_days(days)
	} else if !journal.valid_date(review_after) {
		return fail("review_after 格式应为 YYYY-MM-DD")
	} else if review_after < today {
		return fail(fmt.tprintf("review_after 不能早于今天（%s）", today))
	}

	ts := journal.now_string()
	entry := obj(
		{"kind", q("annotation")},
		{"cast_id", q(id)},
		{"ts", q(ts)},
		{"stance", q(stance)},
		{"confidence", fmt.tprintf("%.2f", conf)},
		{"prediction", q(prediction)},
		{"summary", q(summary) if summary != "" else ""},
		{"review_after", q(review_after)},
		{"client", q(c.client) if c.client != "" else ""},
		{"server", q(VERSION)},
	)
	if !journal.append_line(entry) { return fail(fmt.tprintf("日志写入失败：%s", journal.path())) }

	du_note := ""
	if du, _ := cs.entry["du"].(json.Boolean); du { du_note = "\n（此卦为重摇所得，记为“渎”，复盘时不计入统计。）" }
	text := fmt.tprintf("已记下 %s 的解读：%s，把握 %.0f%%\n预测：%s\n复盘日：%s（到期后我会在起卦或查日志时提醒）%s",
		id, stance_zh(stance), conf * 100, prediction, review_after, du_note)
	return {text = text, structured = obj({"id", q(id)}, {"stance", q(stance)}, {"confidence", fmt.tprintf("%.2f", conf)}, {"review_after", q(review_after)}, {"saved", "true"})}
}
