/* odin-gua — 易经起卦 MCP 服务器（stdio）。

   排卦归程序，解卦归模型：随机数、互错综变、取辞位置都由这里确定并记入日志；
   agent 拿到结果后再联系问题去解释。 */
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

import "gua"
import "journal"
import "mcp"

VERSION :: "0.3.0"

obj :: mcp.obj
q :: mcp.q
num :: mcp.num
arr :: mcp.arr
boolean :: mcp.boolean

INSTRUCTIONS :: `易经起卦服务（I Ching casting）。
- 用户想起卦、占卜、问卦时（如“起一卦”“帮我卜一下”“cast the I Ching”），调用 cast，并把用户关心的事提炼成一句 question 传入；不必让用户自己抛硬币。
- 卦象由服务器随机数决定并自动记入日志。绝不要自行编造卦象。同一问题 72 小时内服务器不会重摇，会返回原卦（初筮告，再三渎）；不要换个说法绕开。只有情况确已改变、用户明确要求时，才传 recast:true 和 reason，新卦记为“渎”、不计入统计。
- 解读以返回的 reading（朱熹取辞规则：该读哪条卦辞或爻辞）为主线；reading.focus 里已附原文 text_zh（通行本）与 text_en（Legge 1882 英译），请据原文引述，不要凭记忆改写经文。结合本卦、之卦、互卦与问题来讲；先给结论倾向，再给理由。
- 讲完解读后立刻调用 annotate 记下：stance（倾向）、confidence（0–1）、prediction（一句将来能对照检验的具体判断）、review_after 或 review_in_days（何时复盘，按问题时间尺度定）。每卦只记一次，写下不改。
- cast 与 journal 的结果里若有“复盘提醒”，在回答末尾顺便问用户那几件事结果如何。
- 提醒用户：这是供自我反思的参考，不构成任何决策（包括投资）依据。
- 查卦用 lookup，看互错综变用 relations，回看历史用 journal（due:true 只看到期待复盘的）。`

main :: proc() {
	if ok, msg := gua.self_check(); !ok {
		fmt.eprintln("odin-gua: 数据自检失败:", msg)
		os.exit(1)
	}
	s := mcp.Server{name = "odin-gua", version = VERSION, instructions = INSTRUCTIONS}
	append(&s.tools,
		mcp.Tool{
			name = "cast", title = "起卦",
			description = "起一卦（默认三钱法），返回本卦、动爻、之卦、互卦与按朱熹规则应读的卦辞/爻辞位置，并自动记入卦例日志。必须提供 question。Cast an I Ching hexagram for a question; the result is random, reproducible by seed, and journaled.",
			input_schema = `{"type":"object","properties":{"question":{"type":"string","description":"用户所问之事，一句话"},"method":{"type":"string","enum":["coins","yarrow"],"default":"coins","description":"coins 三钱法；yarrow 大衍筮法概率"},"recast":{"type":"boolean","default":false,"description":"同一问题窗口期内确需重起时才设 true（新卦记为渎）"},"reason":{"type":"string","description":"recast 时必填：情况有何变化"}},"required":["question"]}`,
			handler = tool_cast,
		},
		mcp.Tool{
			name = "lookup", title = "查卦", read_only = true,
			description = "按文王序号(1-64)、中文名、拼音、英文名、Unicode 卦符或六位二进制(自初爻到上爻，1 为阳)查卦。Look up a hexagram by number, name, pinyin, English name, symbol, or 6-bit string.",
			input_schema = `{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}`,
			handler = tool_lookup,
		},
		mcp.Tool{
			name = "relations", title = "互错综变", read_only = true,
			description = "给出一卦的互卦、错卦、综卦；若提供 moving（动爻位置 1-6），再给出之卦与取辞位置。Nuclear, inverse, reverse and changed hexagrams.",
			input_schema = `{"type":"object","properties":{"query":{"type":"string","description":"同 lookup"},"moving":{"type":"array","items":{"type":"integer","minimum":1,"maximum":6},"description":"动爻位置，1 为初爻"}},"required":["query"]}`,
			handler = tool_relations,
		},
		mcp.Tool{
			name = "journal", title = "卦例日志", read_only = true,
			description = "列出最近的起卦记录（新的在前）。Recent casts from the local journal.",
			input_schema = `{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":50,"default":10},"due":{"type":"boolean","default":false,"description":"只看已到复盘日、尚未复盘的卦例"}}}`,
			handler = tool_journal,
		},
		mcp.Tool{
			name = "annotate", title = "记下解读",
			description = "解卦后记下模型的解读与可检验的预测，供日后复盘。每卦只记一次，写下不改。Record the model's reading and a checkable prediction for later review; one per cast, immutable.",
			input_schema = `{"type":"object","properties":{"id":{"type":"string","description":"cast 返回的卦例 id"},"stance":{"type":"string","enum":["favorable","unfavorable","mixed","unclear"],"description":"倾向：偏吉/偏凶/参半/不明"},"confidence":{"type":"number","minimum":0,"maximum":1,"description":"对此倾向的把握"},"prediction":{"type":"string","description":"一句将来能对照结果检验的具体判断"},"summary":{"type":"string","description":"解读要点（可选）"},"review_after":{"type":"string","description":"复盘日期 YYYY-MM-DD"},"review_in_days":{"type":"integer","minimum":1,"description":"或：几天后复盘（默认 14）"}},"required":["id","stance","confidence","prediction"]}`,
			handler = tool_annotate,
		},
	)
	s.list_resources = list_resources
	s.read_resource = read_resource
	s.resource_templates = []mcp.Resource{{uri = "hexagram://{number}", name = "卦", description = "第 number 卦（1-64）的基本信息", mime = "application/json"}}

	arg := os.args[1] if len(os.args) > 1 else ""
	switch arg {
	case "":
		mcp.run(&s)
	case "--version":
		fmt.println("odin-gua", VERSION)
		fmt.println("texts", gua.texts_id())
	case "--self-test":
		fmt.printf("odin-gua %s 自检\n", VERSION)
		if !self_test(&s) { fmt.println("自检失败"); os.exit(1) }
		fmt.println("自检通过")
	case "--print-config":
		print_config()
	case "--http":
		// 远程客户端（如 Perplexity 自定义连接器）用：只监听 127.0.0.1，由隧道或反代提供 HTTPS
		port := 8765
		if len(os.args) > 2 {
			if p, ok := strconv.parse_int(os.args[2]); ok { port = p }
		}
		token := os.get_env("GUA_HTTP_TOKEN", context.allocator)
		if token == "" { fmt.eprintln("警告：未设 GUA_HTTP_TOKEN，任何能访问端口的人都能调用") }
		if !mcp.serve_http(&s, port, token) { os.exit(1) }
	case:
		fmt.println(USAGE)
		if arg != "-h" && arg != "--help" { os.exit(2) }
	}
}

USAGE :: `odin-gua — 易经起卦 MCP 服务器（stdio）

用法：
  odin-gua                 以 MCP stdio 服务器运行（由客户端启动）
  odin-gua --self-test     进程内自检（不写用户日志）
  odin-gua --print-config  打印客户端配置 JSON
  odin-gua --http [端口]   以 Streamable HTTP 运行（127.0.0.1，默认 8765；令牌取 GUA_HTTP_TOKEN）
  odin-gua --version`

// ---------- 卦的 JSON ----------

trigram_json :: proc(i: u8) -> string {
	t := gua.TRIGRAMS[i]
	return obj({"name_zh", q(t.zh)}, {"symbol", q(t.symbol)}, {"name_en", q(t.en)}, {"nature", q(t.nature)}, {"pinyin", q(t.pinyin)})
}

hex_json :: proc(g: gua.Gua) -> string {
	n := gua.number(g)
	return obj(
		{"number", num(n)},
		{"symbol", q(gua.symbol(n))},
		{"name_zh", q(gua.NAME_ZH[n])},
		{"pinyin", q(gua.PINYIN[n])},
		{"name_en", q(gua.NAME_EN[n])},
		{"name_trad", q(gua.name_trad[n])},
		{"name_legge", q(gua.name_legge[n])},
		{"binary", q(gua.binary_string(g))},
		{"judgment_zh", q(gua.judgment_text(n))},
		{"judgment_en", q(gua.judgment_text(n, .En))},
		{"upper", trigram_json(gua.upper(g))},
		{"lower", trigram_json(gua.lower(g))},
	)
}

positions :: proc(m: gua.Gua) -> string {
	items := make([dynamic]string, context.temp_allocator)
	for y in gua.Yao { if y in m { append(&items, num(int(y) + 1)) } }
	return arr(items[:])
}

moving_names :: proc(g, m: gua.Gua) -> string {
	items := make([dynamic]string, context.temp_allocator)
	for y in gua.Yao { if y in m { append(&items, gua.line_name(y, y in g)) } }
	return strings.join(items[:], "、", context.temp_allocator)
}

reading_json :: proc(g, m: gua.Gua) -> string {
	r := gua.reading(g, m)
	items := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< r.n {
		it := r.items[i]
		h := g if it.source == .Primary else gua.bian(g, m)
		kind: string
		switch it.kind {
		case .Judgment: kind = "judgment"
		case .Line:     kind = "line"
		case .Yong:     kind = "yong"
		}
		append(&items, obj(
			{"hexagram", num(gua.number(h))},
			{"source", q("primary" if it.source == .Primary else "changed")},
			{"kind", q(kind)},
			{"line", num(int(it.line) + 1) if it.kind == .Line else ""},
			{"line_name", q(gua.line_name(it.line, it.line in h)) if it.kind == .Line else ""},
			{"main", boolean(it.main)},
			{"label", q(gua.focus_label(it, g, m))},
			{"text_zh", q(gua.focus_text(it, g, m, .Zh))},
			{"text_en", q(gua.focus_text(it, g, m, .En))},
		))
	}
	return obj({"moving_count", num(r.moving_count)}, {"rule", q(r.rule)}, {"focus", arr(items[:])})
}

// ---------- 查找 ----------

normalize :: proc(s: string) -> string {
	t := strings.to_lower(strings.trim_space(s), context.temp_allocator)
	t, _ = strings.remove_all(t, " ", context.temp_allocator)
	t, _ = strings.replace_all(t, "ü", "u", context.temp_allocator)
	t, _ = strings.replace_all(t, "v", "u", context.temp_allocator)
	return t
}

find :: proc(query: string) -> []gua.Gua {
	out := make([dynamic]gua.Gua, context.temp_allocator)
	qs := strings.trim_space(query)
	if qs == "" { return nil }

	if n, ok := strconv.parse_int(qs, 10); ok {
		if n >= 1 && n <= 64 { append(&out, gua.BY_NUMBER[n]) }
		return out[:]
	}
	if len(qs) == 6 && strings.count(qs, "0") + strings.count(qs, "1") == 6 {
		g: gua.Gua
		for i in 0 ..< 6 { if qs[i] == '1' { g += {gua.Yao(i)} } }
		append(&out, g)
		return out[:]
	}
	if r, w := utf8.decode_rune_in_string(qs); w == len(qs) && r >= 0x4DC0 && r <= 0x4DFF {
		append(&out, gua.BY_NUMBER[int(r - 0x4DC0) + 1])
		return out[:]
	}
	key := normalize(qs)
	key_nothe := strings.trim_prefix(key, "the")
	for n in 1 ..= 64 {
		en := normalize(gua.NAME_EN[n])
		if qs == gua.NAME_ZH[n] || key == normalize(gua.PINYIN[n]) || key == en || key_nothe == strings.trim_prefix(en, "the") {
			append(&out, gua.BY_NUMBER[n])
		}
	}
	return out[:]
}

find_one :: proc(query: string) -> (g: gua.Gua, err: string) {
	hits := find(query)
	switch len(hits) {
	case 0: return {}, fmt.tprintf("找不到卦：%s", query)
	case 1: return hits[0], ""
	}
	names := make([dynamic]string, context.temp_allocator)
	for h in hits { append(&names, fmt.tprintf("%d %s", gua.number(h), gua.NAME_ZH[gua.number(h)])) }
	return {}, fmt.tprintf("“%s”对应多卦，请指明：%s", query, strings.join(names[:], "、", context.temp_allocator))
}

fail :: proc(msg: string) -> mcp.Tool_Result { return {text = msg, is_error = true} }

str_arg :: proc(c: ^mcp.Call, k: string) -> string {
	v, _ := c.args[k].(json.String)
	return v
}

// ---------- 工具 ----------

tool_cast :: proc(c: ^mcp.Call) -> mcp.Tool_Result {
	question := strings.trim_space(str_arg(c, "question"))
	if question == "" { return fail("cast 需要 question：请把用户所问之事提炼成一句话再起卦。") }
	method := gua.Method.Coins
	switch str_arg(c, "method") {
	case "", "coins": method = .Coins
	case "yarrow":    method = .Yarrow
	case:             return fail("method 只能是 coins 或 yarrow")
	}

	cases, _ := journal.load_cases()
	recast, _ := c.args["recast"].(json.Boolean)
	reason := strings.trim_space(str_arg(c, "reason"))
	prev, dup := find_recent_same(cases[:], question)
	if dup && !recast {
		pid := journal.str(prev.entry, "id")
		text := fmt.tprintf("此问已于 %s 起过卦：%s %s\n原问：%s\n\n初筮告，再三渎：不重摇，请沿用原卦解读（journal 可查看）。若情况确已改变，可带 recast:true 与 reason 重起，新卦记为“渎”、不计入统计。",
			journal.str(prev.entry, "ts"), pid, case_title(prev.entry), journal.str(prev.entry, "question"))
		return {text = text, structured = obj({"duplicate_of", q(pid)}, {"journaled", "false"}, {"cast", "false"})}
	}
	if dup && reason == "" { return fail("recast 需要 reason：说明情况有何变化") }
	du := dup && recast

	seed := journal.random_u64()
	if s := os.get_env("GUA_SEED", context.temp_allocator); s != "" { // 仅测试用
		if v, ok := strconv.parse_u64(s); ok { seed = v }
	}
	cs := gua.cast_with_seed(seed, method)
	g, m := gua.primary(cs), gua.moving(cs)
	z := gua.bian(g, m)
	ts := journal.now_string()
	id := journal.new_id(ts)
	seed_hex := fmt.tprintf("%016x", seed)

	entry := obj(
		{"kind", q("cast")},
		{"id", q(id)},
		{"ts", q(ts)},
		{"question", q(question)},
		{"method", q(gua.METHOD_NAME[method])},
		{"seed", q(seed_hex)},
		{"values", q(gua.values_string(cs))},
		{"primary", num(gua.number(g))},
		{"changed", num(gua.number(z)) if m != {} else "null"},
		{"moving", positions(m)},
		{"client", q(c.client) if c.client != "" else ""},
		{"server", q(VERSION)},
		{"texts", q(gua.texts_id())},
		{"du", "true" if du else ""},
		{"duplicate_of", q(journal.str(prev.entry, "id")) if du else ""},
		{"reason", q(reason) if du else ""},
	)
	saved := journal.append_line(entry)

	r := gua.reading(g, m)
	b := strings.builder_make(context.temp_allocator)
	method_zh := "三钱法" if method == .Coins else "大衍筮法"
	fmt.sbprintf(&b, "起卦 %s · %s · %s\n问：%s\n\n", id, method_zh, ts, question)
	fmt.sbprintf(&b, "本卦 %s\n%s\n", gua.title(g), gua.draw(g, cs.values[:]))
	if m != {} {
		fmt.sbprintf(&b, "动爻：%s\n之卦 %s\n", moving_names(g, m), gua.title(z))
	} else {
		fmt.sbprintf(&b, "动爻：无\n")
	}
	fmt.sbprintf(&b, "互卦 %s\n\n", gua.title(gua.hu(g)))
	fmt.sbprintf(&b, "取辞（朱熹）：%s\n", r.rule)
	write_focus(&b, r, g, m)
	if du { fmt.sbprintf(&b, "\n此卦为重摇（原卦 %s），记为“渎”，不计入统计。", journal.str(prev.entry, "id")) }
	fmt.sbprintf(&b, "\n仅供自我反思，不构成决策依据。")
	fmt.sbprintf(&b, "\n解读后请调用 annotate(id=%s) 记下倾向、把握与可检验的预测。", id)
	due := journal.due(cases[:], journal.today())
	write_due(&b, due)
	if !saved { fmt.sbprintf(&b, "\n（注意：日志写入失败：%s）", journal.path()) }

	structured := obj(
		{"id", q(id)},
		{"ts", q(ts)},
		{"question", q(question)},
		{"method", q(gua.METHOD_NAME[method])},
		{"seed", q(seed_hex)},
		{"values", q(gua.values_string(cs))},
		{"primary", hex_json(g)},
		{"moving", positions(m)},
		{"changed", hex_json(z) if m != {} else "null"},
		{"nuclear", hex_json(gua.hu(g))},
		{"reading", reading_json(g, m)},
		{"journaled", boolean(saved)},
		{"du", "true" if du else ""},
		{"due_reviews", due_json(due) if len(due) > 0 else ""},
	)
	return {text = strings.to_string(b), structured = structured}
}

tool_lookup :: proc(c: ^mcp.Call) -> mcp.Tool_Result {
	query := str_arg(c, "query")
	hits := find(query)
	if len(hits) == 0 { return fail(fmt.tprintf("找不到卦：%s", query)) }
	b := strings.builder_make(context.temp_allocator)
	items := make([dynamic]string, context.temp_allocator)
	for h, i in hits {
		if i > 0 { strings.write_string(&b, "\n\n") }
		n := gua.number(h)
		fmt.sbprintf(&b, "%s\n%s\n卦辞：%s\n%s", gua.title(h), gua.draw(h), gua.judgment_text(n), gua.judgment_text(n, .En))
		append(&items, hex_json(h))
	}
	return {text = strings.to_string(b), structured = obj({"results", arr(items[:])})}
}

tool_relations :: proc(c: ^mcp.Call) -> mcp.Tool_Result {
	g, err := find_one(str_arg(c, "query"))
	if err != "" { return fail(err) }
	m: gua.Gua
	if a, ok := c.args["moving"].(json.Array); ok {
		for v in a {
			p, is_int := v.(json.Integer)
			if !is_int || p < 1 || p > 6 { return fail("moving 里的爻位必须是 1 到 6 的整数") }
			m += {gua.Yao(p - 1)}
		}
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "本卦 %s\n互卦 %s\n错卦 %s\n综卦 %s", gua.title(g), gua.title(gua.hu(g)), gua.title(gua.cuo(g)), gua.title(gua.zong(g)))
	if m != {} {
		r := gua.reading(g, m)
		fmt.sbprintf(&b, "\n动爻 %s → 之卦 %s\n取辞（朱熹）：%s\n", moving_names(g, m), gua.title(gua.bian(g, m)), r.rule)
		write_focus(&b, r, g, m)
	}
	structured := obj(
		{"hexagram", hex_json(g)},
		{"nuclear", hex_json(gua.hu(g))},
		{"inverse", hex_json(gua.cuo(g))},
		{"reverse", hex_json(gua.zong(g))},
		{"moving", positions(m) if m != {} else ""},
		{"changed", hex_json(gua.bian(g, m)) if m != {} else ""},
		{"reading", reading_json(g, m) if m != {} else ""},
	)
	return {text = strings.to_string(b), structured = structured}
}

tool_journal :: proc(c: ^mcp.Call) -> mcp.Tool_Result {
	limit := 10
	if v, ok := c.args["limit"].(json.Integer); ok { limit = clamp(int(v), 1, 50) }
	only_due, _ := c.args["due"].(json.Boolean)
	cases, _ := journal.load_cases()
	today := journal.today()
	due := journal.due(cases[:], today)
	rows := make([dynamic]journal.Case, context.temp_allocator)
	if only_due {
		for d in due { if len(rows) < limit { append(&rows, d) } }
	} else {
		#reverse for cs in cases { if len(rows) < limit { append(&rows, cs) } }
	}
	if len(rows) == 0 {
		msg := "没有到期待复盘的卦例。" if only_due else fmt.tprintf("还没有起卦记录（%s）。", journal.path())
		return {text = msg, structured = obj({"entries", "[]"}, {"due_count", num(len(due))}, {"path", q(journal.path())})}
	}
	b := strings.builder_make(context.temp_allocator)
	if len(due) > 0 && !only_due { fmt.sbprintf(&b, "%d 卦已到复盘日（journal due:true 查看）。\n\n", len(due)) }
	items := make([dynamic]string, context.temp_allocator)
	for cs, i in rows {
		o := cs.entry
		ts := journal.str(o, "ts")
		if i > 0 { strings.write_byte(&b, '\n') }
		fmt.sbprintf(&b, "%s  %s  %s  [%s]\n    问：%s", ts[:min(len(ts), 16)], journal.str(o, "id"), case_title(o), case_status(cs, today), journal.str(o, "question"))
		raw, _ := json.marshal(o, allocator = context.temp_allocator)
		note := ""
		if cs.note != nil {
			n := cs.note
			conf, _ := n["confidence"].(json.Float)
			fmt.sbprintf(&b, "\n    解读：%s，把握 %.0f%%；预测：%s", stance_zh(journal.str(n, "stance")), f64(conf) * 100, journal.str(n, "prediction"))
			nraw, _ := json.marshal(n, allocator = context.temp_allocator)
			note = string(nraw)
		}
		append(&items, mcp_merge(string(raw), obj({"status", q(case_status(cs, today))}, {"annotation", note})))
	}
	return {text = strings.to_string(b), structured = obj({"entries", arr(items[:])}, {"due_count", num(len(due))}, {"path", q(journal.path())})}
}

// ---------- 资源 ----------

list_resources :: proc() -> []mcp.Resource {
	out := make([]mcp.Resource, 64, context.temp_allocator)
	for n in 1 ..= 64 {
		out[n - 1] = {
			uri  = fmt.tprintf("hexagram://%d", n),
			name = fmt.tprintf("%s %d %s %s", gua.symbol(n), n, gua.NAME_ZH[n], gua.NAME_EN[n]),
			mime = "application/json",
		}
	}
	return out
}

read_resource :: proc(uri: string) -> (text: string, mime: string, ok: bool) {
	if !strings.has_prefix(uri, "hexagram://") { return }
	n, isnum := strconv.parse_int(uri[len("hexagram://"):], 10)
	if !isnum || n < 1 || n > 64 { return }
	g := gua.BY_NUMBER[n]
	lines := make([dynamic]string, context.temp_allocator)
	for y in gua.Yao {
		append(&lines, obj(
			{"line", num(int(y) + 1)},
			{"line_name", q(gua.line_name(y, y in g))},
			{"text_zh", q(gua.line_text(n, y))},
			{"text_en", q(gua.line_text(n, y, .En))},
		))
	}
	yong := ""
	if yz := gua.yong_text(n); yz != "" {
		yong = obj({"name", q("用九" if n == 1 else "用六")}, {"text_zh", q(yz)}, {"text_en", q(gua.yong_text(n, .En))})
	}
	full := obj({"lines", arr(lines[:])}, {"yong", yong}, {"texts", q(gua.texts_id())})
	return mcp_merge(hex_json(g), full), "application/json", true
}

// 合并两个 JSON 对象字面量
mcp_merge :: proc(a, b: string) -> string {
	return strings.concatenate({a[:len(a) - 1], ",", b[1:]}, context.temp_allocator)
}

// 取辞项逐条列出，附中英原文
write_focus :: proc(b: ^strings.Builder, r: gua.Reading, g, m: gua.Gua) {
	for i in 0 ..< r.n {
		it := r.items[i]
		fmt.sbprintf(b, "  → %s\n    %s\n    %s\n", gua.focus_label(it, g, m), gua.focus_text(it, g, m, .Zh), gua.focus_text(it, g, m, .En))
	}
}
