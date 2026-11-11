# Odin MCP 现状（2026-11-11 调研）

## 现有库

| 库 | 协议版本 | 规模 | 许可 | 状态 |
|---|---|---|---|---|
| [RainerXE/odin-mcp](https://github.com/RainerXE/odin-mcp) | 2025-11-25（`initialize` 握手） | ~1.4k 行 | MIT | 被 [olt](https://github.com/RainerXE/odintooling) 实际使用；示例用 dev-2026-07 编译通过，stdio 冒烟 `initialize` + `tools/list` 正常，二进制 554 KB |
| [Guilospanck/mcp-odin](https://github.com/Guilospanck/mcp-odin) | 2026-07-28（`server/discover`，无握手） | ~3.1k 行 | MIT | 手写，仅服务端；tools/resources/prompts 已有，通知与订阅未做 |

两者都是 0 star 的个人项目，官方 SDK 列表中没有 Odin。

## 协议版本的坑

[MCP 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/changelog) 改动很大：

- 去掉 `initialize` / `notifications/initialized`，改为无状态；每个请求在 `_meta` 里带版本与客户端能力。
- 新增必须实现的 `server/discover`。
- 所有结果需要 `resultType`；list 类结果需要 `ttlMs`、`cacheScope`。
- Sampling、Roots、Logging 被标为 deprecated。

## 对本项目的结论

1. 客户端新旧并存，服务器应**同时支持** `initialize`（2025-11-25）与 `server/discover`（2026-07-28）。现有两个库各只覆盖一边。
2. 计划自写一层薄协议（stdio JSON-RPC，估计 300 行左右），参考上述两个 MIT 库。
3. Sampling 被弃用，印证设计：解卦由 agent 完成，再用 `annotate` 写回。
4. 无状态协议下，跨调用状态用服务器生成的句柄（卦例 id）作为普通参数传递，与日志设计一致。
