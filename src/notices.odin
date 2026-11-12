package main

// 更新通告：版本变了之后的第一次工具调用，在结果前附上“这几版改了什么、agent 该怎么用”。
// 上次版本取自日志里最后一条带 server 字段的记录；通告后追加一条 kind=upgrade，
// 所以同一台机器上无论哪个客户端先调用，只通告一次。全新安装（日志为空）不通告。

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "journal"
import "mcp"

Note :: struct { version, text: string }

// 新版本在后。改 VERSION 不写通告，编译不过（见下面的 #assert）。
NOTES :: [?]Note{
	{"0.2.0", "取辞结果附卦辞爻辞原文 reading.focus[].text_zh / text_en（通行本 / Legge 1882），引用时照录，不要凭记忆改写；lookup 附卦辞，hexagram://n 含全卦经文。"},
	{"0.3.0", "新增 annotate：讲完解读立刻记下 stance、confidence（0–1）、prediction（将来能对照检验的一句话）与 review_after/review_in_days，每卦一次、写下不改。到期卦例会以“复盘提醒”附在 cast/journal 结果里，请在回答末尾顺便问用户结果。同一问题 72 小时内服务器不重摇、返回原卦；只有用户明确说情况变了，才带 recast:true 与 reason。"},
	{"0.3.1", "新增本更新通告：版本变化后的第一次调用会附上各版要点。"},
	{"0.4.0", "三钱法会记下每一枚钱的正反：structuredContent.coins 为六爻、每爻三枚，2 是阴（字）、3 是阳（背），自初爻到上爻，三者之和即 values。支持 MCP Apps 的客户端在工具卡片播放这次的 3D 回放；钱面以 coins 为准，不要另编，也不要在解卦正文里插入动图。大衍法没有硬币。同一问题返回原卦时 animate 为 false，是初筮的钱面，不是新的一掷。"},
}

#assert(NOTES[len(NOTES) - 1].version == VERSION, "改了 VERSION 要在 NOTES 末尾补一条更新通告")

@(private = "file")
checked := false

// a < b（按 x.y.z 数字比较）
version_less :: proc(a, b: string) -> bool {
	pa := strings.split(a, ".", context.temp_allocator)
	pb := strings.split(b, ".", context.temp_allocator)
	for i in 0 ..< max(len(pa), len(pb)) {
		x, y := 0, 0
		if i < len(pa) { x = strconv.parse_int(pa[i]) or_else 0 }
		if i < len(pb) { y = strconv.parse_int(pb[i]) or_else 0 }
		if x != y { return x < y }
	}
	return false
}

// 日志里最后一条记录的 server 版本；无日志返回 ""
last_seen_version :: proc() -> string {
	data, err := os.read_entire_file_from_path(journal.path(), context.temp_allocator)
	if err != nil { return "" }
	lines := strings.split_lines(string(data), context.temp_allocator)
	#reverse for l in lines {
		line := strings.trim_space(l)
		if line == "" { continue }
		v, perr := json.parse_string(line, parse_integers = true, allocator = context.temp_allocator)
		if perr != nil { continue }
		o, ok := v.(json.Object)
		if !ok { continue }
		if sv := journal.str(o, "server"); sv != "" { return sv }
	}
	return ""
}

// 从 last 升到 VERSION 之间各版的要点；无需通告返回 ""
update_notice :: proc(last: string) -> string {
	if last == "" || !version_less(last, VERSION) { return "" }
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "【odin-gua 已更新 %s → %s】请按新规则使用：", last, VERSION)
	notes := NOTES
	for n in notes {
		if version_less(last, n.version) && !version_less(VERSION, n.version) {
			fmt.sbprintf(&b, "\n  · %s：%s", n.version, n.text)
		}
	}
	return strings.to_string(b)
}

after_call :: proc(c: ^mcp.Call, tr: ^mcp.Tool_Result) {
	if checked { return }
	checked = true
	last := last_seen_version()
	notice := update_notice(last)
	if notice == "" { return }
	journal.append_line(obj({"kind", q("upgrade")}, {"ts", q(journal.now_string())}, {"from", q(last)}, {"server", q(VERSION)}, {"client", q(c.client) if c.client != "" else ""}))
	tr.text = strings.concatenate({notice, "\n\n", tr.text}, context.temp_allocator)
	if strings.has_prefix(tr.structured, "{") {
		tr.structured = mcp_merge(tr.structured, obj({"update_notice", obj({"from", q(last)}, {"to", q(VERSION)}, {"text", q(notice)})}))
	}
}
