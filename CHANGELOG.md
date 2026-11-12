# Changelog

## Unreleased

- 仓库公开；MIT 许可证。
- 英文 README（`README.en.md`），中英互链。
- `curl ... | bash` 一行安装，不依赖 gh。

## 0.1.1 — 2026-11-12

- `install.sh`：一条命令准备 Odin dev-2026-07（缺则下载并校验 SHA256）、编译、自检，并注册到 Claude Code、Codex、Cursor、Claude Desktop；支持 `--dry-run`、`--clients`、`--prefix`、`--uninstall`，改 JSON 前自动备份。
- `AGENTS.md`（`CLAUDE.md` 引入）：agent 可直接读取执行的安装、验证、排错与使用规则。
- 新参数 `--self-test`（进程内 8 项自检，不依赖 Python）、`--print-config`、`--version`、`--help`；未知参数退出码 2。

## 0.1.0 — 2026-11-11

- MCP stdio 服务器，同时支持 2025-11-25 及更早（`initialize`）与 2026-07-28（`server/discover`、无握手）。
- 工具：`cast`、`lookup`、`relations`、`journal`；资源 `hexagram://{number}`。
- 起卦：三钱法与大衍筮法概率；种子记入日志，可复现。
- 取辞：朱熹《易学启蒙》动爻规则（0–6 爻动），返回应读卦辞/爻辞位置。
- 数据：Unicode 卦符与英文名（由 `tools/gen_names_en.py` 生成）、拼音、八卦；启动自检文王表。
- 日志：`~/.gua/journal.jsonl`，只追加，0600，带本地时区时间戳。
- 尚未包含卦辞爻辞原文。
