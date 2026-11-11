#!/usr/bin/env python3
"""stdio 冒烟测试：分别用旧版（initialize 握手）和新版（2026-07-28，_meta 带版本）对话。
用法：python3 tests/smoke.py bin/odin-gua"""
import json, os, subprocess, sys, tempfile

BIN = sys.argv[1] if len(sys.argv) > 1 else "bin/odin-gua"
home = tempfile.mkdtemp(prefix="gua-")
env = dict(os.environ, GUA_HOME=home, GUA_TZ="Asia/Shanghai")
fails = 0

def check(cond, what):
    global fails
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond: fails += 1

def session(msgs, extra_env=None):
    p = subprocess.run([BIN], input="\n".join(json.dumps(m, ensure_ascii=False) for m in msgs) + "\n",
                       capture_output=True, text=True, env=dict(env, **(extra_env or {})), timeout=10)
    if p.stderr.strip(): print("  stderr:", p.stderr.strip())
    return [json.loads(l) for l in p.stdout.splitlines() if l.strip()]

print("== 旧版协议 2025-11-25")
out = session([
    {"jsonrpc": "2.0", "id": 1, "method": "initialize",
     "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "smoke-legacy", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "cast", "arguments": {"question": "下周的谈判"}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "lookup", "arguments": {"query": "䷾"}}},
    {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "lookup", "arguments": {"query": "qian"}}},
    {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "relations", "arguments": {"query": "小畜", "moving": [3, 6]}}},
    {"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "cast", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 8, "method": "nope"},
    {"jsonrpc": "2.0", "id": 9, "method": "resources/read", "params": {"uri": "hexagram://11"}},
    {"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": {"name": "journal", "arguments": {}}},
], {"GUA_SEED": "42"})
by = {m["id"]: m for m in out}
check(len(out) == 10, f"10 条回复（通知不回）: {len(out)}")
check(by[1]["result"]["protocolVersion"] == "2025-11-25", "initialize 协商版本")
check("instructions" in by[1]["result"], "initialize 带 instructions")
check("resultType" not in by[1]["result"], "旧版结果不带 resultType")
check([t["name"] for t in by[2]["result"]["tools"]] == ["cast", "lookup", "relations", "journal"], "四个工具")
c = by[3]["result"]; sc = c["structuredContent"]
check(not c["isError"] and sc["journaled"], "cast 成功并记入日志")
check(sc["question"] == "下周的谈判" and len(sc["values"]) == 6, "cast 结构化字段")
print("\n" + c["content"][0]["text"] + "\n")
check(by[4]["result"]["structuredContent"]["results"][0]["number"] == 63, "按 Unicode 卦符查到既济")
check(len(by[5]["result"]["structuredContent"]["results"]) == 2, "拼音 qian 命中 乾、谦 两卦")
r6 = by[6]["result"]["structuredContent"]
check(r6["changed"]["number"] == 60 and r6["nuclear"]["number"] == 38, "小畜 三、上爻动 → 节；互卦 睽")
check(r6["reading"]["focus"][1]["label"] == "本卦小畜 上九（主）", "二爻动以上爻为主")
check(by[7]["result"]["isError"], "缺 question 报工具错误")
check(by[8]["error"]["code"] == -32601, "未知方法 -32601")
check(json.loads(by[9]["result"]["contents"][0]["text"])["name_zh"] == "泰", "resources/read 泰")
check(len(by[10]["result"]["structuredContent"]["entries"]) == 1, "journal 读到 1 条")

print("== 新版协议 2026-07-28")
meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": {"name": "smoke-modern", "version": "1"}}
out = session([
    {"jsonrpc": "2.0", "id": "d", "method": "server/discover", "params": {"_meta": meta}},
    {"jsonrpc": "2.0", "id": "l", "method": "tools/list", "params": {"_meta": meta}},
    {"jsonrpc": "2.0", "id": "c", "method": "tools/call", "params": {"_meta": meta, "name": "cast", "arguments": {"question": "要不要换工作", "method": "yarrow"}}},
    {"jsonrpc": "2.0", "id": "x", "method": "tools/list", "params": {"_meta": {"io.modelcontextprotocol/protocolVersion": "1900-01-01"}}},
    {"jsonrpc": "2.0", "id": "j", "method": "tools/call", "params": {"_meta": meta, "name": "journal", "arguments": {"limit": 5}}},
])
by = {m["id"]: m for m in out}
d = by["d"]["result"]
check(d["resultType"] == "complete" and "2026-07-28" in d["supportedVersions"], "server/discover")
check(d["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "odin-gua", "结果 _meta 带 serverInfo")
check(by["l"]["result"]["ttlMs"] > 0 and by["l"]["result"]["cacheScope"] == "public", "tools/list 带缓存字段")
check(by["c"]["result"]["resultType"] == "complete" and "ttlMs" not in by["c"]["result"], "tools/call 不带缓存字段")
check(by["x"]["error"]["code"] == -32022 and "2026-07-28" in by["x"]["error"]["data"]["supported"], "不支持的版本 -32022")
ents = by["j"]["result"]["structuredContent"]["entries"]
check(len(ents) == 2 and ents[0]["client"] == "smoke-modern" and ents[1]["client"] == "smoke-legacy", "两个客户端共用日志，新的在前")
print("\n" + by["j"]["result"]["content"][0]["text"] + "\n")

import datetime as _dt
ts = _dt.datetime.fromisoformat(sc["ts"])
now = _dt.datetime.now(_dt.timezone.utc)
check(abs((now - ts).total_seconds()) < 60 and ts.utcoffset().total_seconds() == 8 * 3600, f"时间戳为正确的当地时间: {sc['ts']}")
mode = oct(os.stat(os.path.join(home, "journal.jsonl")).st_mode & 0o777)
check(mode == "0o600", f"日志权限 {mode}")
print("通过" if fails == 0 else f"{fails} 项失败")
sys.exit(1 if fails else 0)
