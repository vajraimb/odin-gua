# odin-gua

中文 | [English](README.en.md)

用 Odin 写的易经起卦 MCP 服务器：agent 里随时起卦、按规则取原文、自动记录，并像评估模型一样复盘。

> 仅供娱乐与自我反思，不构成任何决策（含投资）依据。

## 安装

一条命令（macOS / Linux）：自动准备 Odin dev-2026-07（缺则下载并校验 SHA256）、编译、自检、注册到本机的 Claude Code / Codex / Cursor / Claude Desktop：

```bash
curl -fsSL https://raw.githubusercontent.com/vajraimb/odin-gua/main/install.sh | bash
# 或在克隆好的仓库里：
./install.sh            # --dry-run 先看会做什么；--clients none 只安装；--uninstall 卸载
```

也可以直接让 agent 来装：它会读 [AGENTS.md](AGENTS.md)（Claude Code 经 `CLAUDE.md` 引入）照做。装好后重启客户端，在对话里说“帮我起一卦，问下周的谈判”即可。

手动编译：

```bash
./build.sh          # 生成 bin/odin-gua（约 450 KB，无依赖）
./build.sh test     # 再跑单元测试与新旧两代协议的 stdio 冒烟测试
```

命令行参数：

| 参数 | 作用 |
|---|---|
| （无） | 以 stdio MCP 服务器运行 |
| `--self-test` | 进程内跑 8 项协议与工具自检（用临时目录，不写用户日志） |
| `--print-config` | 打印本二进制的 `mcpServers` 配置片段 |
| `--version` / `--help` | 版本 / 用法 |

环境变量（都可不设）：

| 变量 | 作用 |
|---|---|
| `GUA_HOME` | 日志目录，默认 `~/.gua` |
| `GUA_TZ` | 时间戳时区（IANA 名，如 `Asia/Shanghai`），默认系统时区 |

日志 `~/.gua/journal.jsonl` 只追加、权限 0600，所有客户端共用。

## 协议

同时支持两代 MCP：

- 旧版 2024-11-05 … 2025-11-25：`initialize` 握手。
- 新版 2026-07-28：无握手，`server/discover`，结果带 `resultType`，list/read 带 `ttlMs`、`cacheScope`。

请求 `_meta` 里带 `io.modelcontextprotocol/protocolVersion` 就按新版回复，否则按旧版。已用 MCP Inspector 2.14.0 CLI 验证。

## 远程客户端

只接受 HTTPS 远程 MCP 的客户端（如 Perplexity 自定义连接器）可用 HTTP 模式，再由隧道或反向代理提供 HTTPS：

```sh
GUA_HTTP_TOKEN=$(openssl rand -hex 16) odin-gua --http 8765   # 只监听 127.0.0.1
# 连接器 URL：https://<你的域名>/mcp/<令牌>，认证选 None，传输选 Streamable HTTP
```

日志写在运行服务的那台机器上。

## 设计原则

- **排卦归程序，解卦归模型。** 随机数、互错综变、取哪条爻辞都由代码确定并可复现；模型只负责联系问题去解释。
- **用户零操作。** 用户只提问；起卦、记录、复盘提醒都自动完成。
- **复盘即评估。** 每一卦都是一次“预测”，事后对照结果、做安慰剂对照与评委打分。

## 为什么用 Odin

- 单个无依赖二进制，stdio 启动毫秒级，不需要 uv / npx。
- Unicode 卦符、英文名、文王表、卦辞爻辞（中英 450 条）编译进二进制，离线可用；经文用 `#load` 零拷贝嵌入。
- 数据正确性在编译期保证：`#load_hash` 封印经文文件，约 1800 条 `#assert` 逐条核对偏移、爻题、卦画（中文“九/六”与英文“undivided/divided”都须与卦的比特一致）；另有启动自检（64 卦齐全、文王序“非综即错”成对、Unicode 映射）。
- `bit_set[Yao; u8]`：一爻一位，错卦 `~g`、变卦 `g ~ moving`。

## 数据

- 卦符：U+4DC0–U+4DFF，按文王序排列，`0x4DC0 + 序号 - 1`。
- 英文名：Unicode 字符名（如 `HEXAGRAM FOR THE CREATIVE HEAVEN`）。
- 八卦：U+2630–U+2637；单爻：⚊ U+268A、⚋ U+268B。
- 卦辞爻辞：通行本繁体，底本 ctext 武英殿本《周易正義》，以維基文庫、四部叢刊、Project Gutenberg 互校；英文 Legge (1882，公有领域)。来源、改字与异文见 [data/SOURCES.md](data/SOURCES.md)。

## 工具

| 工具 | 状态 | 作用 |
|---|---|---|
| `cast` | ✅ 0.1 | 起卦（三钱法/大衍法概率），必须带 `question`；返回本卦、动爻、之卦、互卦、取辞及中英原文，自动记日志 |
| `lookup` | ✅ 0.1 | 按序号、中文名、拼音、英文名、Unicode 卦符、六位二进制查卦；附卦辞 |
| `relations` | ✅ 0.1 | 互、错、综；给动爻时再给之卦与取辞 |
| `journal` | ✅ 0.1 | 最近的起卦记录 |
| `annotate` | 计划 | 写回模型解读：倾向、置信度、复盘日期 |
| `review` | 计划 | 记录事后结果 |
| `report` | 计划 | 命中率、Brier 校准、安慰剂对照、评委点评 |

资源：`hexagram://1` … `hexagram://64`（模板 `hexagram://{number}`），含卦辞、六爻爻辞与用九/用六，中英对照。

## 规则

- **取辞**：按朱熹《易学启蒙》常用规则，由动爻数决定读哪段原文。
- **不再三**（计划）：同一问题短时间内重复起卦标记为“渎”，不计入统计（防止挑结果）。
- **安慰剂对照**（计划）：复盘时盲解一个随机卦，与本卦解读比较贴合度。

## 路线

1. ✅ `cast` / `lookup` / `relations` / `journal` + 自动日志 + Unicode/英文名 + 取辞位置
2. ✅ 卦辞爻辞原文入库（中英 450 条，编译期校验）
3. `annotate`、复盘提醒、防重摇
4. `review` / `report`、安慰剂对照、评委打分

## 许可

[MIT](LICENSE)。

## 目录

- `src/gua` — 卦的表示、文王表、起卦、取辞规则（含单元测试）
- `src/mcp` — stdio JSON-RPC 协议层（新旧两代）
- `src/journal` — 卦例日志
- `src/main.odin` — 工具与资源、命令行参数
- `src/selftest.odin` — `--self-test` 与 `--print-config`
- `install.sh` — 一键安装/注册/卸载
- `AGENTS.md` / `CLAUDE.md` — 给 agent 读的安装与使用说明
- `tests/smoke.py` — 协议冒烟测试
- `tools/gen_names_en.py` — 从 Unicode 字符名生成英文卦名表
- `tools/gen_texts.py` — 由 `data/` 经文生成偏移表与编译期断言
- `data/` — 经文（`zhouyi.txt`、`legge.txt`）、逐条来源 `provenance.tsv`、`SOURCES.md`
- `proto/qigua` — 起卦与互错综变原型（含文王表自检）
- `proto/gua_types` — “卦即类型”编译期实验
- `docs/mcp-survey.md` — Odin MCP 现状调研
