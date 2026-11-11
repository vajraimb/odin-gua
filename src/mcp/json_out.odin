package mcp

import "core:fmt"
import "core:strings"

// 极简 JSON 输出：用字符串拼接，所有中间结果放在 temp_allocator。

// 带引号并转义的 JSON 字符串
q :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_byte(&b, '"')
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		switch c {
		case '"':  strings.write_string(&b, `\"`)
		case '\\': strings.write_string(&b, `\\`)
		case '\n': strings.write_string(&b, `\n`)
		case '\r': strings.write_string(&b, `\r`)
		case '\t': strings.write_string(&b, `\t`)
		case:
			if c < 0x20 {
				strings.write_string(&b, fmt.tprintf(`\u%04x`, c))
			} else {
				strings.write_byte(&b, c)
			}
		}
	}
	strings.write_byte(&b, '"')
	return strings.to_string(b)
}

// 把若干已是 JSON 的片段拼成数组
arr :: proc(items: []string) -> string {
	return strings.concatenate({"[", strings.join(items, ",", context.temp_allocator), "]"}, context.temp_allocator)
}

// 键值对：obj({"a", "1"}, {"b", q("x")})；值必须已是 JSON
KV :: struct { k, v: string }

obj :: proc(kvs: ..KV) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_byte(&b, '{')
	first := true
	for kv in kvs {
		if kv.v == "" { continue } // 空值视为省略
		if !first { strings.write_byte(&b, ',') }
		first = false
		strings.write_string(&b, q(kv.k))
		strings.write_byte(&b, ':')
		strings.write_string(&b, kv.v)
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

num :: proc(n: $T) -> string { return fmt.tprint(n) }
boolean :: proc(v: bool) -> string { return "true" if v else "false" }
