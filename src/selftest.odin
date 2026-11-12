package main

import "core:fmt"
import "core:os"
import "core:strings"

import "mcp"

/* odin-gua --self-test：不依赖 Python，在进程内走一遍新旧两代协议。
   日志写到临时目录，不碰用户的 ~/.gua。安装脚本与 agent 用它验证安装。 */
self_test :: proc(s: ^mcp.Server) -> bool {
	tmp, terr := os.make_directory_temp("", "gua-selftest-*", context.allocator)
	if terr != nil {
		fmt.eprintln("self-test: 无法创建临时目录:", terr)
		return false
	}
	defer os.remove_all(tmp)
	os.set_env("GUA_HOME", tmp)
	os.set_env("GUA_SEED", "42")

	Case :: struct { name, req: string, want: []string }
	M :: `"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}`
	cases := []Case{
		{"旧版 initialize", `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"self-test","version":"1"}}}`, {`"protocolVersion":"2025-11-25"`, `"instructions"`}},
		{"旧版 tools/list", `{"jsonrpc":"2.0","id":2,"method":"tools/list"}`, {`"name":"cast"`, `"name":"lookup"`, `"name":"relations"`, `"name":"journal"`}},
		{"cast 起卦并记日志", `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cast","arguments":{"question":"自检"}}}`, {`"isError":false`, `"journaled":true`, `"reading"`}},
		{"lookup ䷾", `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lookup","arguments":{"query":"䷾"}}}`, {`"number":63`, `既济`}},
		{"relations 小畜", `{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"relations","arguments":{"query":"小畜","moving":[3,6]}}}`, {`"changed":{"number":60`}},
		{"journal", `{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"journal","arguments":{}}}`, {`自检`}},
		{"新版 server/discover", `{"jsonrpc":"2.0","id":7,"method":"server/discover","params":{` + M + `}}`, {`"resultType":"complete"`, `"supportedVersions"`, `"ttlMs"`}},
		{"新版 版本不符", `{"jsonrpc":"2.0","id":8,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1900-01-01"}}}`, {`-32022`}},
	}

	ok := true
	for c in cases {
		out, _ := mcp.handle(s, c.req)
		pass := true
		for w in c.want { if !strings.contains(out, w) { pass = false } }
		fmt.printf("  %s  %s\n", "ok  " if pass else "FAIL", c.name)
		if !pass {
			fmt.printf("        回复: %s\n", out[:min(len(out), 300)])
			ok = false
		}
		free_all(context.temp_allocator)
	}
	os.unset_env("GUA_SEED")
	return ok
}

// odin-gua --print-config：打印可直接粘进客户端配置的 JSON
print_config :: proc() {
	exe, err := os.get_executable_path(context.temp_allocator)
	if err != nil { exe = "/abs/path/to/odin-gua" }
	// 注意：fmt 把 { } 当格式符，所以用拼接
	fmt.println(strings.concatenate({"{\n  \"mcpServers\": {\n    \"odin-gua\": { \"command\": ", mcp.q(exe), " }\n  }\n}"}, context.temp_allocator))
}
