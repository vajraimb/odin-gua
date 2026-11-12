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
    {"jsonrpc": "2.0", "id": 11, "method": "resources/read", "params": {"uri": "ui://odin-gua/coins"}},
], {"GUA_SEED": "42"})
by = {m["id"]: m for m in out}
check(len(out) == 11, f"11 条回复（通知不回）: {len(out)}")
check(by[1]["result"]["protocolVersion"] == "2025-11-25", "initialize 协商版本")
check("instructions" in by[1]["result"], "initialize 带 instructions")
check("resultType" not in by[1]["result"], "旧版结果不带 resultType")
check([t["name"] for t in by[2]["result"]["tools"]] == ["cast", "lookup", "relations", "journal", "annotate"], "五个工具")
cast_tool = next(t for t in by[2]["result"]["tools"] if t["name"] == "cast")
check(cast_tool.get("_meta", {}).get("ui", {}).get("resourceUri") == "ui://odin-gua/coins", "cast 声明掷钱界面")
c = by[3]["result"]; sc = c["structuredContent"]
check(not c["isError"] and sc["journaled"], "cast 成功并记入日志")
check(sc["question"] == "下周的谈判" and len(sc["values"]) == 6, "cast 结构化字段")
coins = sc["coins"]
check(sc["animate"] is True and len(coins) == 6 and all(
    sum(row) == int(sc["values"][i]) and set(row) <= {2, 3} for i, row in enumerate(coins)
), "三钱法记下每枚钱，且与爻值相符")
check("钱面（初爻→上爻" in c["content"][0]["text"], "文本列出钱面")
print("\n" + c["content"][0]["text"] + "\n")
check(all(f["text_zh"] and f["text_en"] for f in sc["reading"]["focus"]), "cast 取辞附中英原文")
check(sc["reading"]["focus"][0]["text_zh"] in c["content"][0]["text"], "cast 文本里引出原文")
check(by[4]["result"]["structuredContent"]["results"][0]["number"] == 63, "按 Unicode 卦符查到既济")
check(len(by[5]["result"]["structuredContent"]["results"]) == 2, "拼音 qian 命中 乾、谦 两卦")
r6 = by[6]["result"]["structuredContent"]
check(r6["changed"]["number"] == 60 and r6["nuclear"]["number"] == 38, "小畜 三、上爻动 → 节；互卦 睽")
check(r6["reading"]["focus"][1]["label"] == "本卦小畜 上九（主）", "二爻动以上爻为主")
check(r6["reading"]["focus"][1]["text_zh"] == "既雨既處，尚德載，婦貞厲。月幾望，君子征凶。", "小畜上九爻辞")
check(by[7]["result"]["isError"], "缺 question 报工具错误")
check(by[8]["error"]["code"] == -32601, "未知方法 -32601")
tai = json.loads(by[9]["result"]["contents"][0]["text"])
check(tai["name_zh"] == "泰" and tai["judgment_zh"] == "小往大來，吉亨。" and len(tai["lines"]) == 6 and "yong" not in tai, "resources/read 泰 带卦辞爻辞")
check(len(by[10]["result"]["structuredContent"]["entries"]) == 1, "journal 读到 1 条")
ui = by[11]["result"]["contents"][0]
check(ui["mimeType"] == "text/html;profile=mcp-app" and "ui/initialize" in ui["text"], "掷钱界面是 MCP App")
check(ui.get("_meta", {}).get("ui", {}).get("prefersBorder") is False, "界面不要粗边框")

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
yc = by["c"]["result"]["structuredContent"]
check(yc["method"] == "yarrow" and "coins" not in yc and yc["animate"] is False, "大衍法不抛钱")
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
print("== 第 3 步：annotate、复盘提醒、防重摇")
home3 = tempfile.mkdtemp()
def call(name, args, extra=None, cid=2):
    msgs = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "smoke-step3", "version": "1"}}},
            {"jsonrpc": "2.0", "id": cid, "method": "tools/call", "params": {"name": name, "arguments": args}}]
    return {m["id"]: m for m in session(msgs, dict({"GUA_HOME": home3}, **(extra or {})))}[cid]["result"]
a = call("cast", {"question": "要不要接这个项目？"})
aid = a["structuredContent"]["id"]
check("annotate(id=" + aid in a["content"][0]["text"], "cast 提示调用 annotate")
d = call("cast", {"question": "要不要接 这个项目"})
check(d["structuredContent"].get("duplicate_of") == aid and not d["isError"], "相似问题不重摇，返回原卦")
check("再三渎" in d["content"][0]["text"], "说明不再三")
check(d["structuredContent"].get("animate") is False and d["structuredContent"].get("coins") == a["structuredContent"]["coins"], "不再三回放初筮钱面")
check(call("cast", {"question": "要不要接这个项目", "recast": True})["isError"], "recast 无 reason 报错")
r = call("cast", {"question": "要不要接这个项目", "recast": True, "reason": "对方改了报价"})
check(r["structuredContent"].get("du") is True, "recast+reason：新卦记为渎")
check(call("cast", {"question": "要不要接这个项目"})["structuredContent"].get("duplicate_of") == aid, "渎卦不作为原卦，仍指向初筮")
check(not call("cast", {"question": "今年要不要搬家"})["isError"], "不同问题照常起卦")
check(call("cast", {"question": "要不要接这个项目"}, {"GUA_RECAST_HOURS": "0"})["structuredContent"].get("duplicate_of") is None, "GUA_RECAST_HOURS=0 关闭防重摇")
check(call("annotate", {"id": aid, "stance": "favorable", "confidence": 0.7})["isError"], "缺 prediction 报错")
check(call("annotate", {"id": aid, "stance": "good", "confidence": 0.7, "prediction": "x"})["isError"], "stance 枚举校验")
check(call("annotate", {"id": "g00000000-000000", "stance": "mixed", "confidence": 0.5, "prediction": "x"})["isError"], "未知 id 报错")
import datetime as _d0
today = _d0.datetime.now(_d0.timezone(_d0.timedelta(hours=8))).date().isoformat()
check(call("annotate", {"id": aid, "stance": "mixed", "confidence": 0.5, "prediction": "x", "review_after": "2000-01-01"})["isError"], "复盘日不能早于今天")
n = call("annotate", {"id": aid, "stance": "favorable", "confidence": 0.7, "prediction": "两周内谈成，但预算比预期少", "review_after": today}, {"TZ": "Asia/Shanghai"})
check(not n["isError"] and n["structuredContent"]["review_after"] == today, "annotate 记下解读")
check(call("annotate", {"id": aid, "stance": "unfavorable", "confidence": 0.9, "prediction": "改主意"})["isError"], "落笔不改：第二次 annotate 报错")
j = call("journal", {"due": True}, {"TZ": "Asia/Shanghai"})
check(len(j["structuredContent"]["entries"]) == 1 and j["structuredContent"]["entries"][0]["annotation"]["prediction"].startswith("两周内"), "journal due:true 列出到期卦例")
k = call("cast", {"question": "下个月去不去伦敦"}, {"TZ": "Asia/Shanghai"})
check("复盘提醒" in k["content"][0]["text"] and k["structuredContent"]["due_reviews"][0]["id"] == aid, "起新卦时附复盘提醒")
st = [e["status"] for e in call("journal", {"limit": 50}, {"TZ": "Asia/Shanghai"})["structuredContent"]["entries"]]
check(any(x.startswith("渎") for x in st) and any(x.startswith("已到复盘日") for x in st) and "待解读" in st, f"journal 状态: {st}")
print(); print(call("journal", {}, {"TZ": "Asia/Shanghai"})["content"][0]["text"]); print()

print("== 更新通告")
home4 = tempfile.mkdtemp()
with open(os.path.join(home4, "journal.jsonl"), "w") as f:
    f.write(json.dumps({"kind": "cast", "id": "g20261101-000001", "ts": "2026-11-01T10:00:00+08:00", "question": "旧问题", "primary": 1, "server": "0.2.0"}) + "\n")
u1 = call("lookup", {"query": "乾"}, {"GUA_HOME": home4})
t1 = u1["content"][0]["text"]
check(t1.startswith("【odin-gua 已更新 0.2.0 →") and "annotate" in t1 and "0.2.0：" not in t1, "从 0.2.0 升级：只通告之后各版")
check(u1["structuredContent"]["update_notice"]["from"] == "0.2.0", "structuredContent 带 update_notice")
u2 = call("lookup", {"query": "乾"}, {"GUA_HOME": home4})
check("已更新" not in u2["content"][0]["text"] and "update_notice" not in u2["structuredContent"], "只通告一次（跨进程）")
last = json.loads(open(os.path.join(home4, "journal.jsonl")).read().splitlines()[-1])
check(last["kind"] == "upgrade" and last["from"] == "0.2.0", "日志记下 upgrade")
check("已更新" not in call("lookup", {"query": "坤"}, {"GUA_HOME": tempfile.mkdtemp()})["content"][0]["text"], "全新安装不通告")
print("  " + t1.split("\n\n")[0].replace("\n", "\n  "))

print("== Streamable HTTP（--http）")
import socket, time, urllib.request, urllib.error
sk = socket.socket(); sk.bind(("127.0.0.1", 0)); port = sk.getsockname()[1]; sk.close()
henv = dict(os.environ, GUA_HOME=home, GUA_HTTP_TOKEN="t0ken", TZ="Asia/Shanghai")
hp = subprocess.Popen([BIN, "--http", str(port)], env=henv, stderr=subprocess.DEVNULL)
def post(path, body, hdr=None):
    rq = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=json.dumps(body).encode(), headers=hdr or {}, method="POST")
    try:
        with urllib.request.urlopen(rq, timeout=5) as r: return r.status, r.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()
for _ in range(50):
    try: urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1); break
    except Exception: time.sleep(0.1)
try:
    check(post("/mcp", {})[0] == 401, "无令牌 401")
    st, b = post("/mcp/t0ken", {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke-http", "version": "1"}}})
    check(st == 200 and json.loads(b)["result"]["protocolVersion"] == "2025-06-18", "路径令牌 initialize")
    check(post("/mcp/t0ken", {"jsonrpc": "2.0", "method": "notifications/initialized"})[0] == 202, "通知 202")
    st, b = post("/mcp", {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "relations", "arguments": {"query": "乾", "moving": [1]}}}, {"Authorization": "Bearer t0ken"})
    check(st == 200 and "潛龍" in b, "Bearer 令牌 relations 带原文")
finally:
    hp.terminate(); hp.wait()
print("通过" if fails == 0 else f"{fails} 项失败")
sys.exit(1 if fails else 0)
