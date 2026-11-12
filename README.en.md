# odin-gua

[中文](README.md) | English

An I Ching (易经) MCP server written in Odin. Cast a hexagram from inside your agent at any moment, get the line texts to read by fixed rules, keep an automatic journal, and (next) review past casts the way you would evaluate a model.

> For entertainment and self-reflection only. Not a basis for any decision, including investment.

## Install

One command (macOS / Linux). It fetches Odin dev-2026-07 if needed (SHA256-verified), builds, runs a self-test, and registers with the Claude Code, Codex, Cursor and Claude Desktop installs it finds:

```bash
curl -fsSL https://raw.githubusercontent.com/vajraimb/odin-gua/main/install.sh | bash
# or, inside a clone:
./install.sh            # --dry-run to preview; --clients none to skip registration; --uninstall to remove
```

Or let your agent do it: point it at this repo and it will follow [AGENTS.md](AGENTS.md) (Claude Code picks it up through `CLAUDE.md`). Restart your client, then just say "cast a hexagram about next week's negotiation".

**Updating**: rerun the same command (it runs `git pull` and reinstalls), then start a new session. The first call to a new version prefixes its result with what changed, so the agent picks up new rules without being told. See the "更新" section of [AGENTS.md](AGENTS.md).

Manual build:

```bash
./build.sh          # builds bin/odin-gua (~450 KB, no dependencies)
./build.sh test     # plus unit tests and stdio smoke tests for both protocol generations
```

Command-line flags:

| Flag | Effect |
|---|---|
| (none) | Run as a stdio MCP server |
| `--self-test` | 9 in-process protocol and tool checks (uses a temp dir, never touches your journal) |
| `--print-config` | Print the `mcpServers` snippet for this binary |
| `--version` / `--help` | Version / usage |

Environment variables (all optional):

| Variable | Effect |
|---|---|
| `GUA_HOME` | Journal directory, default `~/.gua` |
| `GUA_TZ` | Timestamp time zone (IANA name such as `Europe/London`), default system zone |

The journal `~/.gua/journal.jsonl` is append-only, mode 0600, and shared by every client.

## Protocol

Both MCP generations are supported:

- Legacy 2024-11-05 … 2025-11-25: `initialize` handshake.
- Modern 2026-07-28: no handshake, `server/discover`, results carry `resultType`, list/read carry `ttlMs` and `cacheScope`.

A request whose `_meta` contains `io.modelcontextprotocol/protocolVersion` gets a modern reply; otherwise legacy. Verified with the MCP Inspector 2.14.0 CLI.

## Remote clients

Clients that only accept remote HTTPS MCP servers (such as Perplexity custom connectors) can use HTTP mode behind a tunnel or reverse proxy:

```sh
GUA_HTTP_TOKEN=$(openssl rand -hex 16) odin-gua --http 8765   # listens on 127.0.0.1 only
# connector URL: https://<your-host>/mcp/<token>, auth None, transport Streamable HTTP
```

The journal is written on the machine that runs the server.

## Design

- **Code casts, the model interprets.** Randomness, derived hexagrams and which line to read are decided by code and reproducible from a seed; the model only relates them to your question.
- **Zero effort for the user.** You only ask. Casting and journaling happen automatically.
- **Review as evaluation.** Every cast is a prediction to be checked later against what happened, with a placebo control and a judge model (planned).

## Why Odin

- A single dependency-free binary that starts in milliseconds over stdio. No uv, no npx.
- Unicode symbols, English names, the King Wen table and all 450 judgment/line texts (Chinese and English) are compiled in and work offline; texts are embedded zero-copy with `#load`.
- Integrity is checked at compile time: `#load_hash` seals the text files, and about 1,800 `#assert`s verify every offset, line heading and hexagram bit (the Chinese 九/六 and the English "undivided/divided" must both match the hexagram).
- Data integrity is enforced with `#assert` (e.g. `size_of(Gua) == 1`) and a startup self-check (all 64 present, King Wen pairs are inverses or complements, Unicode mapping).
- `bit_set[Yao; u8]`: one bit per line. The complement is `~g`, the changed hexagram is `g ~ moving`.

## Data

- Symbols: U+4DC0–U+4DFF in King Wen order, `0x4DC0 + number - 1`.
- English names: Unicode character names (e.g. `HEXAGRAM FOR THE CREATIVE HEAVEN`).
- Trigrams: U+2630–U+2637; single lines: ⚊ U+268A, ⚋ U+268B.
- Judgment and line texts: the received text in traditional characters (base: ctext, Wuyingdian 周易正義; collated against Wikisource, the Sibu Congkan edition and Project Gutenberg). English: Legge (1882, public domain). See [data/SOURCES.md](data/SOURCES.md).

## Tools

| Tool | Status | Purpose |
|---|---|---|
| `cast` | ✅ 0.4 | Cast (three-coin or yarrow-stalk probabilities); `question` is required. Returns primary, moving lines, changed and nuclear hexagrams, which texts to read, and journals the cast. The three-coin method also records each coin; hosts that support MCP Apps replay that toss beside the tool call |
| `lookup` | ✅ 0.1 | Find a hexagram by number, Chinese name, pinyin, English name, Unicode symbol or 6-bit string |
| `relations` | ✅ 0.1 | Nuclear, complement and inverse; with moving lines, also the changed hexagram and reading |
| `journal` | ✅ 0.1 | Recent casts |
| `annotate` | ✅ 0.3 | Store the model's reading: stance, confidence (0–1), a checkable prediction, review date; once per cast, immutable |
| `review` | planned | Record what actually happened |
| `report` | planned | Hit rate, Brier calibration, placebo comparison, judge commentary |

Resources: `hexagram://1` … `hexagram://64` (template `hexagram://{number}`). `ui://odin-gua/coins` is the coin replay (MCP Apps): three coins about one line high, then the six lines grow out beneath them. It plays back the recorded faces and does not roll again; the yarrow method shows the six lines only. Hosts without that extension still get the text result.

## Rules

- **Which text to read:** Zhu Xi's rules from 《易学启蒙》, chosen by the number of moving lines.
- **No recasting**: the same question (character-bigram similarity ≥ 0.7 after stripping punctuation) within 72 hours returns the original cast instead of a new one. A deliberate recast needs `recast:true` and a `reason`; it is marked 渎 and excluded from statistics. Tune with `GUA_RECAST_HOURS` (0 disables).
- **Immutable readings**: only the first `annotate` per cast is kept, so reviews compare against what was actually predicted.
- **Review reminders**: casts past their review date are listed in every `cast` result and counted at the top of `journal`, so the agent can ask how things turned out.
- **Placebo control** (planned): at review time, a random hexagram is read blind and compared with the real one.

## Roadmap

1. ✅ `cast` / `lookup` / `relations` / `journal`, automatic journal, Unicode and English names, reading positions
2. ✅ Judgment and line texts (450 entries, Chinese + English, compile-time checked)
3. ✅ `annotate`, review reminders, recast detection
4. `review` / `report`, placebo control, judge scoring

## License

[MIT](LICENSE).

## Layout

- `src/gua` — hexagram representation, King Wen table, casting, reading rules (with unit tests)
- `src/mcp` — stdio JSON-RPC layer (both generations)
- `src/journal` — journal
- `src/main.odin` — tools, resources, CLI flags
- `src/selftest.odin` — `--self-test` and `--print-config`
- `install.sh` — install, register, uninstall
- `AGENTS.md` / `CLAUDE.md` — install and usage instructions for agents (Chinese)
- `tests/smoke.py` — protocol smoke tests
- `tools/gen_names_en.py` — generates English names from Unicode character names
- `tools/gen_texts.py` — generates the offset tables and compile-time asserts from `data/`
- `data/` — texts (`zhouyi.txt`, `legge.txt`), per-entry `provenance.tsv`, `SOURCES.md`
- `proto/qigua` — casting and derived-hexagram prototype
- `proto/gua_types` — "hexagrams as types" compile-time experiment
- `docs/mcp-survey.md` — survey of MCP in Odin (Chinese)
