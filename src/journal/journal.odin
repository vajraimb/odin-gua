/* journal — 卦例日志：每次起卦追加一行 JSON 到 journal.jsonl。

   位置：$GUA_HOME/journal.jsonl，默认 ~/.gua/journal.jsonl。
   所有客户端共用同一个文件，所以在任何 agent 里起的卦都能一起复盘。
   只追加、不改写：后续的解读、结果也会以新行（带同一 id）追加。 */
package journal

import "core:crypto"
import "core:encoding/hex"
import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "core:time/timezone"

FILE_NAME :: "journal.jsonl"

dir :: proc() -> string {
	if d := os.get_env("GUA_HOME", context.temp_allocator); d != "" { return d }
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil || home == "" { return ".gua" }
	p, _ := filepath.join({home, ".gua"}, context.temp_allocator)
	return p
}

path :: proc() -> string {
	p, _ := filepath.join({dir(), FILE_NAME}, context.temp_allocator)
	return p
}

// 本地时区偏移（分钟）。$GUA_TZ 可指定 IANA 时区名，如 Asia/Shanghai。
local_offset_minutes :: proc(t: time.Time) -> int {
	name := os.get_env("GUA_TZ", context.temp_allocator)
	if name == "" { name = os.get_env("TZ", context.temp_allocator) }
	if name == "" { name = "local" }
	reg, ok := timezone.region_load(name, context.temp_allocator)
	if !ok || reg == nil { return 0 }
	dt, ok1 := time.time_to_datetime(t)
	if !ok1 { return 0 }
	local, ok2 := timezone.datetime_to_tz(dt, reg)
	if !ok2 { return 0 }
	local.tz = nil // 把当地钟面时间当作 UTC 读，再与真实时刻相减得偏移
	lt, ok3 := time.datetime_to_time(local)
	if !ok3 { return 0 }
	return int(time.diff(t, lt) / time.Minute)
}

now_string :: proc() -> string {
	t := time.now()
	off := local_offset_minutes(t)
	// time_to_rfc3339 只写偏移标签、不换算钟面，所以先把时刻平移到当地
	s, ok := time.time_to_rfc3339(time.time_add(t, time.Duration(off) * time.Minute), off, false, context.temp_allocator)
	return s if ok else ""
}

random_u64 :: proc() -> u64 {
	b: [8]u8
	crypto.rand_bytes(b[:])
	return transmute(u64)b
}

// 卦例 id：g + 本地日期 + 6 位随机十六进制，如 g20261111-3fa9c2
new_id :: proc(ts: string) -> string {
	b: [3]u8
	crypto.rand_bytes(b[:])
	date := strings.concatenate({ts[0:4], ts[5:7], ts[8:10]}, context.temp_allocator) if len(ts) >= 10 else "00000000"
	return strings.concatenate({"g", date, "-", string(hex.encode(b[:], context.temp_allocator))}, context.temp_allocator)
}

append_line :: proc(line: string) -> bool {
	_ = os.make_directory_all(dir(), os.Permissions{.Read_User, .Write_User, .Execute_User}) // 已存在时报错可忽略，是否可写交给 open 判定
	f, err := os.open(path(), {.Write, .Create, .Append}, os.Permissions{.Read_User, .Write_User}) // 0600：日志含个人问题
	if err != nil { return false }
	defer os.close(f)
	_, e1 := os.write_string(f, line)
	_, e2 := os.write_string(f, "\n")
	return e1 == nil && e2 == nil
}

// 读最近 n 条“起卦”记录（kind == cast），新的在前
recent_casts :: proc(n: int) -> []json.Object {
	data, err := os.read_entire_file_from_path(path(), context.temp_allocator)
	if err != nil { return nil }
	lines := strings.split_lines(string(data), context.temp_allocator)
	out := make([dynamic]json.Object, context.temp_allocator)
	for i := len(lines) - 1; i >= 0 && len(out) < n; i -= 1 {
		l := strings.trim_space(lines[i])
		if l == "" { continue }
		v, perr := json.parse_string(l, parse_integers = true, allocator = context.temp_allocator)
		if perr != nil { continue }
		o, ok := v.(json.Object)
		if !ok { continue }
		if k, _ := o["kind"].(json.String); k != "cast" { continue }
		append(&out, o)
	}
	return out[:]
}
