# AGENTS.md

给 AI agent（Claude Code、Codex、Cursor 等）读的安装与使用说明。用户说“装一下这个仓库”“把 odin-gua 接上”时，照本文件执行，不需要用户动手。

## 这是什么

`odin-gua` 是一个本地 stdio MCP 服务器（单个约 450 KB 的 Odin 二进制，无运行时依赖），提供起卦 `cast`、查卦 `lookup`、互错综变 `relations`、历史 `journal` 四个工具，卦例自动记入 `~/.gua/journal.jsonl`。

## 一键安装

在仓库根目录运行：

```bash
./install.sh
```

脚本按顺序做完以下事情，可重复运行：

1. 找 Odin `dev-2026-07`：PATH 里有且版本匹配就用；否则下载官方 release 到 `~/.gua/toolchain/odin-dev-2026-07`，并用脚本内固定的 SHA256 校验。
2. 编译到 `~/.gua/bin/odin-gua`（`-o:speed -vet -strict-style`）。
3. 运行 `odin-gua --self-test`（8 项，进程内跑，不写用户日志）。
4. 注册到检测到的 MCP 客户端：

| 客户端 | 检测条件 | 注册方式 |
|---|---|---|
| Claude Code | PATH 有 `claude` | `claude mcp add --transport stdio --scope user odin-gua -- ~/.gua/bin/odin-gua` |
| Codex CLI | PATH 有 `codex` | `codex mcp add odin-gua -- ~/.gua/bin/odin-gua` |
| Cursor | 存在 `~/.cursor` | 合并写入 `~/.cursor/mcp.json` |
| Claude Desktop | 存在其配置目录 | 合并写入 `claude_desktop_config.json` |

改 JSON 前会备份为 `*.bak-odin-gua-时间戳`，只增改 `mcpServers.odin-gua` 一项，其他配置不动。

常用参数：

```bash
./install.sh --dry-run                    # 先看会做什么（推荐 agent 先跑一次）
./install.sh --clients claude-code        # 只注册指定客户端，逗号分隔
./install.sh --clients none               # 只安装，打印手动配置 JSON
./install.sh --prefix /opt/gua            # 改安装位置
./install.sh --uninstall                  # 取消注册、删除二进制，保留日志
```

不想先 clone 也可以一行装好（脚本发现不在仓库里，会自动 `git clone` 源码到 `~/.gua/src`，再次运行会 `git pull` 更新）：

```bash
curl -fsSL https://raw.githubusercontent.com/vajraimb/odin-gua/main/install.sh | bash
# 带参数：... | bash -s -- --clients claude-code
```

## 验证

```bash
~/.gua/bin/odin-gua --version
~/.gua/bin/odin-gua --self-test      # 输出“自检通过”且退出码 0
~/.gua/bin/odin-gua --print-config   # 打印 mcpServers 配置片段
```

然后告诉用户：重启客户端或开一个新会话，直接说“帮我起一卦，问……”。Claude Code 里可用 `claude mcp list` 确认。

## 出错时

| 现象 | 处理 |
|---|---|
| macOS 报缺 Xcode Command Line Tools | 让用户运行 `xcode-select --install`，装完重跑 |
| Linux 报缺 clang | `sudo apt install clang`（或对应发行版的包），重跑 |
| SHA256 不匹配 | 不要跳过校验；删掉 `~/.gua/toolchain` 重试，仍不匹配就停下告知用户 |
| clone 失败 | 检查网络与 git；仓库公开，无需登录 |
| 自检失败 | 不要注册；把输出原样给用户看 |
| 客户端里看不到工具 | 重启客户端；检查配置里的路径是绝对路径且文件可执行 |

## Windows（手动）

```bat
# 1. 下载 odin-windows-amd64-dev-2026-07.zip 并解压，需已装 Visual Studio Build Tools
odin build src -out:%USERPROFILE%\.gua\bin\odin-gua.exe -o:speed
%USERPROFILE%\.gua\bin\odin-gua.exe --self-test
# 2. 用 --print-config 的输出加到客户端 MCP 配置
```

## 使用规则（给调用工具的 agent）

- 用户想起卦、占卜、问卦时调用 `cast`，把用户关心的事提炼成一句 `question`；不要让用户自己抛硬币。
- 卦象只能来自 `cast` 的返回。绝不自行编造，也不为同一问题反复起卦挑结果（初筮告，再三渎）。
- 解读以返回的 `reading`（朱熹取辞规则：读哪条卦辞或爻辞）为主线，结合本卦、之卦、互卦与问题；先给倾向，再给理由。
- 提醒用户：仅供自我反思，不构成任何决策（包括投资）依据。
- 查卦用 `lookup`，看互错综变用 `relations`，回看历史用 `journal`。

## 开发

- 工具链固定 Odin `dev-2026-07`；Linux 需 clang。
- `./build.sh` 编译到 `bin/odin-gua`；`./build.sh test` 跑单元测试（`src/gua`）和 `tests/smoke.py`（26 项 stdio 冒烟，新旧两代协议）。
- 编译选项必须过 `-vet -strict-style`。
- 每个请求用 `context.temp_allocator`，请求结束释放；跨请求状态放 `Server.persist`。
- 日志只追加、权限 0600，不改写历史行。
- 测试用 `GUA_SEED` 固定随机数、`GUA_HOME` 指向临时目录，不要碰用户的 `~/.gua`。
- 提交信息末尾加 `Co-authored-by: Perplexity <noreply@perplexity.ai>`。
