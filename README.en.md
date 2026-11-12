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

Manual build:

```bash
./build.sh          # builds bin/odin-gua (~450 KB, no dependencies)
./build.sh test     # plus unit tests and stdio smoke tests for both protocol generations
```

Command-line flags:

| Flag | Effect |
|---|---|
| (none) | Run as a stdio MCP server |
| `--self-test` | 8 in-process protocol and tool checks (uses a temp dir, never touches your journal) |
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

## Design

- **Code casts, the model interprets.** Randomness, derived hexagrams and which line to read are decided by code and reproducible from a seed; the model only relates them to your question.
- **Zero effort for the user.** You only ask. Casting and journaling happen automatically.
- **Review as evaluation.** Every cast is a prediction to be checked later against what happened, with a placebo control and a judge model (planned).

## Why Odin

- A single dependency-free binary that starts in milliseconds over stdio. No uv, no npx.
- Unicode symbols, English names and the King Wen table are compiled in and work offline; line texts will be embedded with `#load` once added.
- Data integrity is enforced with `#assert` (e.g. `size_of(Gua) == 1`) and a startup self-check (all 64 present, King Wen pairs are inverses or complements, Unicode mapping).
- `bit_set[Yao; u8]`: one bit per line. The complement is `~g`, the changed hexagram is `g ~ moving`.

## Data

- Symbols: U+4DC0–U+4DFF in King Wen order, `0x4DC0 + number - 1`.
- English names: Unicode character names (e.g. `HEXAGRAM FOR THE CREATIVE HEAVEN`).
- Trigrams: U+2630–U+2637; single lines: ⚊ U+268A, ⚋ U+268B.
- Judgment and line texts: not yet included. They will be checked line by line against public sources; English will use Legge (1882, public domain).

## Tools

| Tool | Status | Purpose |
|---|---|---|
| `cast` | ✅ 0.1 | Cast (three-coin or yarrow-stalk probabilities); `question` is required. Returns primary, moving lines, changed and nuclear hexagrams, which texts to read, and journals the cast |
| `lookup` | ✅ 0.1 | Find a hexagram by number, Chinese name, pinyin, English name, Unicode symbol or 6-bit string |
| `relations` | ✅ 0.1 | Nuclear, complement and inverse; with moving lines, also the changed hexagram and reading |
| `journal` | ✅ 0.1 | Recent casts |
| `annotate` | planned | Store the model's reading: stance, confidence, review date |
| `review` | planned | Record what actually happened |
| `report` | planned | Hit rate, Brier calibration, placebo comparison, judge commentary |

Resources: `hexagram://1` … `hexagram://64` (template `hexagram://{number}`).

## Rules

- **Which text to read:** Zhu Xi's rules from 《易学启蒙》, chosen by the number of moving lines.
- **No recasting** (planned): repeat casts of the same question shortly after are flagged and excluded from statistics, so results cannot be cherry-picked.
- **Placebo control** (planned): at review time, a random hexagram is read blind and compared with the real one.

## Roadmap

1. ✅ `cast` / `lookup` / `relations` / `journal`, automatic journal, Unicode and English names, reading positions
2. Judgment and line texts (verified line by line)
3. `annotate`, review reminders, recast detection
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
- `proto/qigua` — casting and derived-hexagram prototype
- `proto/gua_types` — "hexagrams as types" compile-time experiment
- `docs/mcp-survey.md` — survey of MCP in Odin (Chinese)
