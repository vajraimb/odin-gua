#!/usr/bin/env bash
# odin-gua 一键安装：准备 Odin 工具链 → 编译 → 自检 → 注册到本机 MCP 客户端。
#
# 可重复运行（幂等）。agent 照 AGENTS.md 执行即可。
#
#   ./install.sh                     安装并注册到检测到的客户端
#   ./install.sh --clients none      只安装，不注册
#   ./install.sh --clients claude-code,codex
#   ./install.sh --prefix DIR        安装到 DIR/bin（默认 ~/.gua）
#   ./install.sh --dry-run           只打印将要执行的操作
#   ./install.sh --uninstall         取消注册并删除二进制（保留卦例日志）
#
# 支持 macOS（arm64/x86_64）与 Linux（x86_64/arm64）。Windows 请见 AGENTS.md 手动步骤。
set -euo pipefail

ODIN_TAG="dev-2026-07"
NAME="odin-gua"
GUA_HOME="${GUA_HOME:-$HOME/.gua}"
PREFIX="${PREFIX:-$GUA_HOME}"
BIN="$PREFIX/bin/$NAME"
CLIENTS="auto"
DRY=0
UNINSTALL=0
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m警告:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m错误:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [[ $DRY == 1 ]]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--clients)   CLIENTS="${2:?--clients 需要参数}"; shift 2 ;;
		--clients=*) CLIENTS="${1#*=}"; shift ;;
		--prefix)    PREFIX="${2:?}"; BIN="$PREFIX/bin/$NAME"; shift 2 ;;
		--dry-run)   DRY=1; shift ;;
		--uninstall) UNINSTALL=1; shift ;;
		-h|--help)   sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die "未知参数: $1（见 --help）" ;;
	esac
done

# ---------- 客户端注册 ----------

ALL_CLIENTS="claude-code codex cursor claude-desktop"

desktop_config() {
	case "$(uname -s)" in
		Darwin) echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
		*)      echo "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
	esac
}

detected() { # 客户端是否存在于本机
	case "$1" in
		claude-code)    have claude ;;
		codex)          have codex ;;
		cursor)         [[ -d "$HOME/.cursor" ]] ;;
		claude-desktop) [[ -d "$(dirname "$(desktop_config)")" ]] ;;
		*) return 1 ;;
	esac
}

client_list() {
	case "$CLIENTS" in
		none) ;;
		auto) for c in $ALL_CLIENTS; do detected "$c" && echo "$c"; done ;;
		all)  echo $ALL_CLIENTS | tr ' ' '\n' ;;
		*)    echo "$CLIENTS" | tr ',' '\n' ;;
	esac
}

# 修改 JSON 配置里的 mcpServers.odin-gua（先备份；需要 python3）
json_edit() { # $1 文件 $2 add|remove
	local f="$1" action="$2"
	have python3 || { warn "没有 python3，无法自动修改 ${f}；请手动加入：$("$BIN" --print-config 2>/dev/null | tr -d '\n')"; return 0; }
	if [[ $DRY == 1 ]]; then printf '  [dry-run] %s %s → %s\n' "$action" "$NAME" "$f"; return 0; fi
	if [[ "$action" == remove && ! -f "$f" ]]; then return 0; fi
	mkdir -p "$(dirname "$f")"
	[[ -f "$f" ]] && cp "$f" "$f.bak-$NAME-$(date +%Y%m%d%H%M%S)"
	python3 - "$f" "$action" "$NAME" "$BIN" <<'PY'
import json, os, sys
path, action, name, binp = sys.argv[1:5]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
servers = data.setdefault("mcpServers", {})
if action == "add":
    servers[name] = {"command": binp}
else:
    servers.pop(name, None)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
}

register() { # $1 客户端
	case "$1" in
		claude-code)
			have claude || { warn "未找到 claude 命令，跳过 Claude Code"; return 0; }
			[[ $DRY == 1 ]] || claude mcp remove --scope user "$NAME" >/dev/null 2>&1 || true
			run claude mcp add --transport stdio --scope user "$NAME" -- "$BIN" ;;
		codex)
			have codex || { warn "未找到 codex 命令，跳过 Codex"; return 0; }
			[[ $DRY == 1 ]] || codex mcp remove "$NAME" >/dev/null 2>&1 || true
			run codex mcp add "$NAME" -- "$BIN" ;;
		cursor)         json_edit "$HOME/.cursor/mcp.json" add ;;
		claude-desktop) json_edit "$(desktop_config)" add ;;
		*) warn "不认识的客户端: $1（可选：${ALL_CLIENTS}）"; return 0 ;;
	esac
	REGISTERED="${REGISTERED:+$REGISTERED }$1"
}

unregister() {
	case "$1" in
		claude-code)    have claude && run claude mcp remove --scope user "$NAME" || true ;;
		codex)          have codex && run codex mcp remove "$NAME" || true ;;
		cursor)         json_edit "$HOME/.cursor/mcp.json" remove ;;
		claude-desktop) json_edit "$(desktop_config)" remove ;;
	esac
}

if [[ $UNINSTALL == 1 ]]; then
	[[ "$CLIENTS" == auto ]] && CLIENTS=all
	for c in $(client_list); do say "取消注册 $c"; unregister "$c"; done
	say "删除 $BIN"
	run rm -f "$BIN"
	say "完成。卦例日志保留在 $GUA_HOME/journal.jsonl（需要时手动删除）。"
	exit 0
fi

# ---------- 工具链 ----------

os_name="$(uname -s)"; arch="$(uname -m)"
case "$os_name/$arch" in
	Linux/x86_64)              ASSET="odin-linux-amd64-$ODIN_TAG.tar.gz"; SHA="43a497f262daac68cd09e8f2b16b7f63929d67886d90c111686239390fac6098" ;;
	Linux/aarch64|Linux/arm64) ASSET="odin-linux-arm64-$ODIN_TAG.tar.gz"; SHA="9eb1e6e08a4563484b36fe36ea9d77b49432a4f3d89c30527bcf3c31fc53ab4c" ;;
	Darwin/arm64)              ASSET="odin-macos-arm64-$ODIN_TAG.tar.gz"; SHA="0712c29beec34eed272c9cf6b62db43c9b37e1f6a5181d04dda7e3e8cb03884c" ;;
	Darwin/x86_64)             ASSET="odin-macos-amd64-$ODIN_TAG.tar.gz"; SHA="91b9facaeb110e36a71c1e941a8299dd0029c985edf61bedd8ebdc1f3673536e" ;;
	*) die "不支持的平台 $os_name/${arch}；请按 AGENTS.md 手动构建" ;;
esac

# 链接器
if [[ $os_name == Darwin ]]; then
	xcode-select -p >/dev/null 2>&1 || die "需要 Xcode Command Line Tools：请运行 xcode-select --install 后重试"
else
	have clang || die "需要 clang 作链接器：如 sudo apt-get install -y clang（Debian/Ubuntu）或 sudo dnf install clang"
fi

sha256() { if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

ODIN=""
if have odin && odin version 2>/dev/null | grep -q "2026-07"; then
	ODIN="$(command -v odin)"
	say "使用已安装的 Odin：${ODIN}（$(odin version)）"
else
	TC="$GUA_HOME/toolchain/odin-$ODIN_TAG"
	ODIN="$TC/odin"
	if [[ -x "$ODIN" ]]; then
		say "使用缓存的 Odin ${ODIN_TAG}：$TC"
	else
		say "下载 Odin ${ODIN_TAG}（${ASSET}）"
		have curl || die "需要 curl"
		url="https://github.com/odin-lang/Odin/releases/download/$ODIN_TAG/$ASSET"
		if [[ $DRY == 1 ]]; then
			printf '  [dry-run] curl %s → 校验 sha256 %s → 解压到 %s\n' "$url" "$SHA" "$TC"
		else
			tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
			curl -fsSL --retry 3 -o "$tmp/odin.tgz" "$url"
			got="$(sha256 "$tmp/odin.tgz")"
			[[ "$got" == "$SHA" ]] || die "Odin 安装包校验失败（期望 ${SHA}，实际 ${got}）"
			mkdir -p "$TC"
			tar xzf "$tmp/odin.tgz" -C "$TC" --strip-components=1
			# macOS 上解压的二进制可能带隔离属性
			[[ $os_name == Darwin ]] && xattr -dr com.apple.quarantine "$TC" 2>/dev/null || true
		fi
	fi
fi

# ---------- 源码 ----------

SRC="$REPO_DIR"
if [[ ! -f "$SRC/src/main.odin" ]]; then
	SRC="$GUA_HOME/src"
	if [[ -d "$SRC/.git" ]]; then
		say "更新源码 $SRC"; run git -C "$SRC" pull --ff-only
	else
		say "获取源码到 $SRC"
		if have gh; then run gh repo clone vajraimb/odin-gua "$SRC"
		else run git clone https://github.com/vajraimb/odin-gua "$SRC"; fi
	fi
fi

# ---------- 编译与自检 ----------

say "编译 → $BIN"
run mkdir -p "$PREFIX/bin"
run "$ODIN" build "$SRC/src" -out:"$BIN" -o:speed -vet -strict-style

say "自检"
if [[ $DRY == 1 ]]; then
	printf '  [dry-run] %s --self-test\n' "$BIN"
else
	"$BIN" --self-test || die "自检失败，未注册任何客户端"
fi

# ---------- 注册 ----------

REGISTERED=""
targets="$(client_list)"
if [[ -z "$targets" ]]; then
	if [[ "$CLIENTS" == auto ]]; then warn "没有检测到 MCP 客户端（claude / codex / Cursor / Claude Desktop）"; fi
else
	for c in $targets; do say "注册到 $c"; register "$c"; done
fi

echo
say "安装完成：$BIN"
if [[ -n "$REGISTERED" ]]; then
	if [[ $DRY == 1 ]]; then echo "    将注册：${REGISTERED}（dry-run，未实际修改）"; else echo "    已注册：${REGISTERED}"; fi
	echo "    请重启客户端或开一个新会话，然后说：“帮我起一卦，问……”"
else
	echo "    未注册任何客户端。手动配置可用："
	[[ $DRY == 1 ]] || "$BIN" --print-config | sed 's/^/    /'
fi
echo "    卦例日志：$GUA_HOME/journal.jsonl"
