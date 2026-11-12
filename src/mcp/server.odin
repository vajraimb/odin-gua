/* mcp — stdio 上的 MCP 服务器，同时支持两代协议：

   - 旧版（2024-11-05 … 2025-11-25）：先 initialize 握手，之后按进程记住所选版本。
   - 新版（2026-07-28）：无握手；每个请求在 params._meta 里带
     io.modelcontextprotocol/protocolVersion，服务器必须实现 server/discover，
     每个结果带 resultType，list/read 类结果带 ttlMs、cacheScope。

   判断依据：请求 _meta 里有协议版本 → 按新版回复；否则按旧版。 */
package mcp

import "base:runtime"
import "core:bufio"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

MODERN_VERSIONS :: []string{"2026-07-28"}
LEGACY_VERSIONS :: []string{"2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"}
META_VERSION :: "io.modelcontextprotocol/protocolVersion"
META_CLIENT :: "io.modelcontextprotocol/clientInfo"

Tool_Result :: struct {
	text:       string, // 给人和模型看的文本
	structured: string, // 结构化 JSON 对象（可为空）
	is_error:   bool,
}

Call :: struct {
	args:   json.Object,
	client: string, // 客户端名，记日志用
}

Tool :: struct {
	name, title, description, input_schema: string,
	read_only:                               bool,
	ui:                                      string, // MCP App 的 ui:// 资源；空则无界面
	handler:                                 proc(c: ^Call) -> Tool_Result,
}

Resource :: struct {
	uri, name, description, mime: string,
}

Server :: struct {
	name, version, instructions: string,
	tools:                       [dynamic]Tool,
	// 资源：list 返回全部；read 由回调生成内容（"" 表示不存在）
	list_resources:              proc() -> []Resource,
	read_resource:               proc(uri: string) -> (text: string, mime: string, meta: string, ok: bool),
	resource_templates:          []Resource,
	legacy_version:              string, // 旧版握手后选定的版本
	client_name:                 string,
	persist:                     runtime.Allocator, // 跨请求保存的数据用它分配
	after_call:                  proc(c: ^Call, tr: ^Tool_Result), // 每次工具调用之后（如附更新通告），可为 nil
}

ERR_PARSE :: -32700
ERR_METHOD :: -32601
ERR_PARAMS :: -32602
ERR_UNSUPPORTED_VERSION :: -32022

log :: proc(args: ..any) {
	fmt.eprintln(..args)
}

run :: proc(s: ^Server) {
	s.persist = context.allocator
	buf: [1 << 16]u8
	r: bufio.Reader
	bufio.reader_init_with_buf(&r, os.to_reader(os.stdin), buf[:])
	defer bufio.reader_destroy(&r)

	for {
		line, err := bufio.reader_read_string(&r, '\n', context.temp_allocator)
		if err != nil && len(line) == 0 { break }
		line = strings.trim_space(line)
		if line != "" {
			if out, has := handle(s, line); has {
				os.write_string(os.stdout, out)
				os.write_string(os.stdout, "\n")
			}
		}
		free_all(context.temp_allocator)
		if err != nil { break }
	}
}

// 处理一条消息；通知（无 id）不回复
handle :: proc(s: ^Server, line: string) -> (out: string, has_reply: bool) {
	if s.persist.procedure == nil { s.persist = context.allocator }
	context.allocator = context.temp_allocator
	v, perr := json.parse_string(line, parse_integers = true)
	if perr != nil {
		return error_reply("null", ERR_PARSE, "Parse error", ""), true
	}
	msg, is_obj := v.(json.Object)
	if !is_obj { return error_reply("null", ERR_PARSE, "Invalid request", ""), true }

	id_raw, has_id := raw_id(msg)
	method, _ := msg["method"].(json.String)
	params, _ := msg["params"].(json.Object)
	if !has_id { return "", false } // 通知：notifications/initialized 等

	meta, _ := params["_meta"].(json.Object)
	modern_ver, modern := meta[META_VERSION].(json.String)
	if modern {
		if !slice.contains(MODERN_VERSIONS, modern_ver) && !slice.contains(LEGACY_VERSIONS, modern_ver) {
			data := obj({"supported", arr(all_versions())}, {"requested", q(modern_ver)})
			return error_reply(id_raw, ERR_UNSUPPORTED_VERSION, "Unsupported protocol version", data), true
		}
		if ci, ok := meta[META_CLIENT].(json.Object); ok {
			if n, ok2 := ci["name"].(json.String); ok2 { remember_client(s, n) }
		}
	}

	result: string
	code := 0
	emsg := ""
	cacheable := false
	ttl := 0
	scope := "public"

	switch method {
	case "initialize":
		want, _ := params["protocolVersion"].(json.String)
		ver := want if slice.contains(LEGACY_VERSIONS, want) else LEGACY_VERSIONS[0]
		s.legacy_version = strings.clone(ver, s.persist)
		if ci, ok := params["clientInfo"].(json.Object); ok {
			if n, ok2 := ci["name"].(json.String); ok2 { remember_client(s, n) }
		}
		result = obj(
			{"protocolVersion", q(ver)},
			{"capabilities", capabilities()},
			{"serverInfo", server_info(s)},
			{"instructions", q(s.instructions)},
		)
	case "server/discover":
		result = obj(
			{"supportedVersions", arr(all_versions())},
			{"capabilities", capabilities()},
			{"instructions", q(s.instructions)},
		)
		modern = true
		cacheable, ttl = true, 3600_000
	case "ping":
		result = "{}"
	case "tools/list":
		items := make([dynamic]string, context.temp_allocator)
		for t in s.tools { append(&items, tool_json(t)) }
		result = obj({"tools", arr(items[:])})
		cacheable, ttl = true, 3600_000
	case "tools/call":
		name, _ := params["name"].(json.String)
		args, _ := params["arguments"].(json.Object)
		found := false
		for t in s.tools {
			if t.name != name { continue }
			found = true
			c := Call{args = args, client = s.client_name}
			tr := t.handler(&c)
			if s.after_call != nil { s.after_call(&c, &tr) }
			result = obj(
				{"content", arr({obj({"type", q("text")}, {"text", q(tr.text)})})},
				{"structuredContent", tr.structured},
				{"isError", boolean(tr.is_error)},
			)
			break
		}
		if !found { code, emsg = ERR_PARAMS, fmt.tprintf("Unknown tool: %s", name) }
	case "resources/list":
		items := make([dynamic]string, context.temp_allocator)
		if s.list_resources != nil {
			for r in s.list_resources() { append(&items, resource_json(r, false)) }
		}
		result = obj({"resources", arr(items[:])})
		cacheable, ttl = true, 86400_000
	case "resources/templates/list":
		items := make([dynamic]string, context.temp_allocator)
		for r in s.resource_templates { append(&items, resource_json(r, true)) }
		result = obj({"resourceTemplates", arr(items[:])})
		cacheable, ttl = true, 86400_000
	case "resources/read":
		uri, _ := params["uri"].(json.String)
		text, mime, meta, ok := "", "", "", false
		if s.read_resource != nil { text, mime, meta, ok = s.read_resource(uri) }
		if !ok {
			code, emsg = ERR_PARAMS, fmt.tprintf("Resource not found: %s", uri)
		} else {
			result = obj({"contents", arr({obj({"uri", q(uri)}, {"mimeType", q(mime)}, {"text", q(text)}, {"_meta", meta})})})
			cacheable, ttl = true, 86400_000
		}
	case "prompts/list":
		result = obj({"prompts", "[]"})
		cacheable, ttl = true, 3600_000
	case:
		code, emsg = ERR_METHOD, fmt.tprintf("Method not found: %s", method)
	}

	if code != 0 { return error_reply(id_raw, code, emsg, ""), true }

	if modern {
		// 新版：补 resultType、_meta.serverInfo；可缓存结果补 ttlMs、cacheScope
		extra := obj(
			{"resultType", q("complete")},
			{"_meta", obj({"io.modelcontextprotocol/serverInfo", server_info(s)})},
			{"ttlMs", num(ttl) if cacheable else ""},
			{"cacheScope", q(scope) if cacheable else ""},
		)
		result = merge(result, extra)
	}
	return obj({"jsonrpc", q("2.0")}, {"id", id_raw}, {"result", result}), true
}

@(private)
remember_client :: proc(s: ^Server, n: string) {
	if s.client_name == n { return }
	if s.client_name != "" { delete(s.client_name, s.persist) }
	s.client_name = strings.clone(n, s.persist)
}

@(private)
all_versions :: proc() -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for v in MODERN_VERSIONS { append(&out, q(v)) }
	for v in LEGACY_VERSIONS { append(&out, q(v)) }
	return out[:]
}

@(private)
capabilities :: proc() -> string {
	return obj({"tools", "{}"}, {"resources", "{}"}, {"prompts", "{}"})
}

@(private)
server_info :: proc(s: ^Server) -> string {
	return obj({"name", q(s.name)}, {"version", q(s.version)})
}

@(private)
tool_json :: proc(t: Tool) -> string {
	ui := ""
	if t.ui != "" { ui = obj({"ui", obj({"resourceUri", q(t.ui)})}) }
	return obj(
		{"name", q(t.name)},
		{"title", q(t.title)},
		{"description", q(t.description)},
		{"inputSchema", t.input_schema},
		{"annotations", obj({"title", q(t.title)}, {"readOnlyHint", boolean(t.read_only)}, {"openWorldHint", "false"})},
		{"_meta", ui},
	)
}

@(private)
resource_json :: proc(r: Resource, template: bool) -> string {
	return obj(
		{"uriTemplate" if template else "uri", q(r.uri)},
		{"name", q(r.name)},
		{"description", q(r.description)},
		{"mimeType", q(r.mime)},
	)
}

// 合并两个 JSON 对象字面量（都以 { } 包裹）
@(private)
merge :: proc(a, b: string) -> string {
	if len(b) <= 2 { return a }
	if len(a) <= 2 { return b }
	return strings.concatenate({a[:len(a) - 1], ",", b[1:]}, context.temp_allocator)
}

@(private)
raw_id :: proc(msg: json.Object) -> (string, bool) {
	v, ok := msg["id"]
	if !ok { return "", false }
	#partial switch x in v {
	case json.Integer: return num(x), true
	case json.String:  return q(x), true
	case json.Float:   return num(x), true
	case json.Null:    return "null", true
	}
	return "null", true
}

@(private)
error_reply :: proc(id: string, code: int, message, data: string) -> string {
	e := obj({"code", num(code)}, {"message", q(message)}, {"data", data})
	return obj({"jsonrpc", q("2.0")}, {"id", id}, {"error", e})
}
