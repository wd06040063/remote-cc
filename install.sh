#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  RemoteCC — 一键交互式部署脚本                                           │
# │  用法: bash install.sh                                                   │
# └─────────────────────────────────────────────────────────────────────────┘
set -euo pipefail

R='\033[0m' B='\033[1m' D='\033[2m'
CYAN='\033[36m' GREEN='\033[32m' YELLOW='\033[33m' RED='\033[31m' GRAY='\033[90m'

# ── 参数解析（banner 之前，set -u 之后需先初始化） ──────────────────────────
# 用法: bash install.sh [-u user] [-p pass] [-P port] [-s] [-y] [-h]
_USER="" _PASS="" _PORT="" _SANDBOX=0 _YES=0 NON_INTERACTIVE=0

while getopts "u:p:P:syh" opt 2>/dev/null; do
  case $opt in
    u) _USER="$OPTARG" ;;
    p) _PASS="$OPTARG" ;;
    P) _PORT="$OPTARG" ;;
    s) _SANDBOX=1 ;;
    y) _YES=1 ;;
    h)
      echo ""
      echo "  用法: bash install.sh [选项]"
      echo ""
      echo "  选项:"
      echo "    -u <user>   管理员用户名（默认: admin）"
      echo "    -p <pass>   管理员密码（必填，传参时跳过交互）"
      echo "    -P <port>   监听端口（默认: 8310）"
      echo "    -s          启用 IS_SANDBOX 危险模式"
      echo "    -y          自动确认所有提示（CI/脚本模式）"
      echo "    -h          显示此帮助"
      echo ""
      echo "  示例（非交互一键安装）:"
      echo "    bash install.sh -u admin -p mypassword -P 8310 -s -y"
      echo ""
      exit 0 ;;
    *) ;;
  esac
done

# 传入密码则进入非交互模式
[[ -n "$_PASS" || "$_YES" == "1" ]] && NON_INTERACTIVE=1

W=$(tput cols 2>/dev/null || echo 80)
HR=$(printf '%0.s─' $(seq 1 $W))

print_banner() {
  clear
  echo -e "${CYAN}${B}"
  echo "  ██████╗  ██████╗ ██████╗ "
  echo "  ██╔══██╗██╔════╝██╔════╝ "
  echo "  ██████╔╝██║     ██║      "
  echo "  ██╔══██╗██║     ██║      "
  echo "  ██║  ██║╚██████╗╚██████╗ "
  echo "  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ "
  echo -e "${R}"
  echo -e "  ${B}RemoteCC${R}  ${GRAY}— 多端协同终端工具${R}"
  echo -e "  ${D}${HR}${R}"
  echo ""
}

step() { echo -e "\n  ${CYAN}${B}▶ $1${R}"; }
ok()   { echo -e "  ${GREEN}✓ $1${R}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${R}"; }
err()  { echo -e "  ${RED}✗ $1${R}"; exit 1; }
info() { echo -e "  ${GRAY}$1${R}"; }
ask()  { echo -en "  ${CYAN}$1${R}" > /dev/tty; }

confirm() {
  local default="${1:-y}"
  local prompt="(Y/n)"; [[ "$default" == "n" ]] && prompt="(y/N)"
  ask "$2 $prompt: "; read -r ans < /dev/tty; ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

input() {
  local def="${1:-}" msg="$2" val
  [[ -n "$def" ]] && ask "$msg [${def}]: " || ask "$msg: "
  read -r val < /dev/tty
  echo "${val:-$def}"
}

proxy_input() {
  local current="${1:-}" msg="$2" val
  ask "$msg: "
  read -r val < /dev/tty
  echo "${val:-$current}"
}

python_ok_for_node_gyp() {
  local py="${1:-}"
  [[ -n "$py" && -x "$py" ]] || return 1
  "$py" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1
}

find_node_gyp_python() {
  local candidate name dir
  local candidates=()

  [[ -n "${npm_config_python:-}" ]] && candidates+=("$npm_config_python")
  [[ -n "${PYTHON:-}" ]] && candidates+=("$PYTHON")

  for name in python3.12 python3.11 python3.10 python3.9 python3.8 python3; do
    candidate="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done

  local search_dirs=()
  if [[ -n "${PYTHON_SEARCH_DIRS:-}" ]]; then
    local IFS=':'
    read -r -a search_dirs <<< "$PYTHON_SEARCH_DIRS"
  fi
  search_dirs+=(
    "$HOME/.pyenv/versions"
    "$HOME/.local"
    "/home/work/tools"
    "/usr/local"
    "/opt"
  )

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for name in python3.12 python3.11 python3.10 python3.9 python3.8; do
      while IFS= read -r candidate; do
        candidates+=("$candidate")
      done < <(find "$dir" -maxdepth 5 -type f -name "$name" -perm -111 2>/dev/null)
    done
  done

  for candidate in "${candidates[@]}"; do
    if python_ok_for_node_gyp "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

compiler_major() {
  local compiler="${1:-}" version major
  [[ -n "$compiler" && -x "$compiler" ]] || return 1
  version="$("$compiler" -dumpfullversion -dumpversion 2>/dev/null || "$compiler" -dumpversion 2>/dev/null || true)"
  major="${version%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$major"
}

find_node_gyp_cxx() {
  local candidate dir major
  local explicit_candidates=()
  local candidates=()
  local search_dirs=()
  local best="" best_major=0

  [[ -n "${CXX:-}" ]] && explicit_candidates+=("$CXX")

  if [[ ${#explicit_candidates[@]} -gt 0 ]]; then
    for candidate in "${explicit_candidates[@]}"; do
      major="$(compiler_major "$candidate" || true)"
      if [[ "$major" =~ ^[0-9]+$ && "$major" -ge 8 ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  candidate="$(command -v g++ 2>/dev/null || true)"
  [[ -n "$candidate" ]] && candidates+=("$candidate")

  if [[ -n "${COMPILER_SEARCH_DIRS:-}" ]]; then
    local IFS=':'
    read -r -a search_dirs <<< "$COMPILER_SEARCH_DIRS"
  fi
  search_dirs+=(
    "/home/opt/compiler"
    "/tmp/rcc-devtoolset9-runtime"
    "/opt/rh"
    "/usr/local"
    "$HOME/.local"
  )

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$dir" -maxdepth 8 -type f -name "g++" -perm -111 2>/dev/null)
  done

  for candidate in "${candidates[@]}"; do
    major="$(compiler_major "$candidate" || true)"
    [[ "$major" =~ ^[0-9]+$ && "$major" -ge 8 ]] || continue
    if [[ -z "$best" || "$major" -lt "$best_major" ]]; then
      best="$candidate"
      best_major="$major"
    fi
  done

  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
}

find_companion_cc() {
  local cxx="${1:-}" dir candidate
  [[ -n "$cxx" ]] || return 1
  dir="$(dirname "$cxx")"
  for candidate in "$dir/gcc" "$(command -v gcc 2>/dev/null || true)" "$dir/cc"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
[[ "$NON_INTERACTIVE" == "0" ]] && print_banner
echo -e "  欢迎使用 ${B}RemoteCC${R} 一键部署向导\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source <(grep -E '^[A-Z_]+=.*' "$SCRIPT_DIR/.env")
  set +a
fi

# ── Step 1: 检查环境 ──────────────────────────────────────────────────────────
step "检查运行环境"

# Node.js
if ! command -v node &>/dev/null; then err "未找到 Node.js，请先安装 Node.js >= v18"; fi
NODE_VER=$(node --version)
NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v\([0-9]*\).*/\1/')
[[ "$NODE_MAJOR" -ge 18 ]] || err "Node.js 版本过低 ($NODE_VER)，需要 >= v18"
ok "Node.js $NODE_VER"

# npm
command -v npm &>/dev/null || err "未找到 npm"
ok "npm $(npm --version)"

# g++（node-pty 在缺少预编译产物时需要本机编译，要求支持 C++17）
if NODE_GYP_CXX="$(find_node_gyp_cxx)"; then
  export CXX="$NODE_GYP_CXX"
  if NODE_GYP_CC="$(find_companion_cc "$CXX")"; then
    export CC="$NODE_GYP_CC"
  fi
  case " ${LDFLAGS:-} " in
    *" -static-libstdc++ "* ) ;;
    * ) export LDFLAGS="${LDFLAGS:+$LDFLAGS }-static-libstdc++" ;;
  esac
  case " ${LDFLAGS:-} " in
    *" -static-libgcc "* ) ;;
    * ) export LDFLAGS="${LDFLAGS:+$LDFLAGS }-static-libgcc" ;;
  esac
  CXX_VER=$("$CXX" --version 2>/dev/null | head -1 || echo "$CXX")
  ok "C++ 编译器: $CXX_VER ($CXX)"
else
  if command -v g++ &>/dev/null; then
    warn "未找到支持 C++17 的 g++；当前默认版本为 $(g++ --version 2>/dev/null | head -1)"
  else
    info "未检测到 g++（如果 node-pty 无预编译产物会安装失败）"
  fi
fi

# ── Step 2: 自动检测 Agent CLI ────────────────────────────────────────────────
step "检测 Agent CLI"

CLAUDE_BIN=""
CODEX_BIN=""

# 自动检测候选路径
NVM_NODE_DIRS=()
if [[ -d "$HOME/.nvm/versions/node" ]]; then
  while IFS= read -r d; do NVM_NODE_DIRS+=("$d"); done < \
    <(ls -1 "$HOME/.nvm/versions/node/" 2>/dev/null | sort -rV | head -5)
fi

CANDIDATES=(
  "$(command -v claude 2>/dev/null || true)"
)
if [[ ${#NVM_NODE_DIRS[@]} -gt 0 ]]; then
  for v in "${NVM_NODE_DIRS[@]}"; do
    CANDIDATES+=("$HOME/.nvm/versions/node/$v/bin/claude")
  done
fi

for c in "${CANDIDATES[@]}"; do
  if [[ -n "$c" && -x "$c" ]]; then
    CLAUDE_BIN="$c"
    CLAUDE_VER=$("$CLAUDE_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    ok "Claude Code: $CLAUDE_BIN ($CLAUDE_VER)"
    break
  fi
done

CODEX_CANDIDATES=(
  "$(command -v codex 2>/dev/null || true)"
)
if [[ ${#NVM_NODE_DIRS[@]} -gt 0 ]]; then
  for v in "${NVM_NODE_DIRS[@]}"; do
    CODEX_CANDIDATES+=("$HOME/.nvm/versions/node/$v/bin/codex")
  done
fi

for c in "${CODEX_CANDIDATES[@]}"; do
  if [[ -n "$c" && -x "$c" ]]; then
    CODEX_BIN="$c"
    CODEX_VER=$("$CODEX_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    ok "Codex: $CODEX_BIN ($CODEX_VER)"
    break
  fi
done

if [[ -z "$CLAUDE_BIN" && -z "$CODEX_BIN" ]]; then
  err "未找到 Claude Code 或 Codex。请先安装其中一个：npm install -g @anthropic-ai/claude-code 或 npm install -g @openai/codex"
fi

# ── Step 3: IS_SANDBOX 自动检测 ──────────────────────────────────────────────
step "检测沙箱环境"

IS_SANDBOX_FLAG=""
if [[ "$_SANDBOX" == "1" || "${IS_SANDBOX:-}" == "1" ]]; then
  warn "启用危险模式（IS_SANDBOX=1）"
  IS_SANDBOX_FLAG="IS_SANDBOX=1 "
else
  info "普通模式（如需危险模式：-s 参数或 IS_SANDBOX=1 环境变量）"
fi

# ── Step 4: 服务配置 ──────────────────────────────────────────────────────────
step "配置服务参数"

if [[ "$NON_INTERACTIVE" == "1" ]]; then
  # 非交互模式：直接用参数，校验必要字段
  RC_USER="${_USER:-${RC_USER:-admin}}"
  RC_PASS="${_PASS:-${RC_PASS:-}}"
  PORT="${_PORT:-${PORT:-8310}}"
  [[ -z "$RC_PASS" ]] && err "非交互模式必须提供密码: -p <password>"
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -le 65535 ]] || err "端口号无效: $PORT"
  ok "用户名: $RC_USER  端口: $PORT"
else
  echo -e "  ${GRAY}配置 Web 界面的登录账号和监听端口，安装完成后用此账号登录浏览器界面。${R}\n"

  RC_USER=$(input "${_USER:-${RC_USER:-admin}}" "管理员用户名（Web 登录用）")

  while true; do
    echo -n "  管理员密码（Web 登录用，输入不显示）: " > /dev/tty; read -rs RC_PASS < /dev/tty; echo "" > /dev/tty
    [[ -z "$RC_PASS" ]] && { echo -e "  ${RED}✗ 密码不能为空${R}"; continue; }
    echo -n "  再次输入密码确认: " > /dev/tty; read -rs RC_PASS2 < /dev/tty; echo "" > /dev/tty
    [[ "$RC_PASS" != "$RC_PASS2" ]] && { echo -e "  ${RED}✗ 两次密码不一致，请重新输入${R}"; continue; }
    [[ "$RC_PASS" == "changeme" ]] && warn "建议使用更安全的密码"
    break
  done

  PORT=$(input "${_PORT:-${PORT:-8310}}" "监听端口（浏览器访问 http://<IP>:<端口>）")
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -le 65535 ]] || err "端口号无效: $PORT"

  echo ""
  ok "配置完成：用户名 ${RC_USER}，端口 ${PORT}"
fi

# ── Step 5: Agent 代理配置 ───────────────────────────────────────────────────
step "配置 Agent 代理"

CLAUDE_PROXY="${CLAUDE_PROXY:-}"
CODEX_PROXY="${CODEX_PROXY:-}"
AGENT_NO_PROXY="${AGENT_NO_PROXY:-localhost,127.0.0.1,::1}"

if [[ "$NON_INTERACTIVE" == "1" ]]; then
  info "非交互模式：沿用环境变量或现有 .env 中的 CLAUDE_PROXY / CODEX_PROXY"
else
  echo -e "  ${GRAY}代理只会注入 Claude/Codex CLI 启动环境，不会写入 RemoteCC 服务全局代理。留空表示不使用代理。${R}\n"
  CODEX_PROXY=$(proxy_input "$CODEX_PROXY" "Codex 代理 URL（示例 http://127.0.0.1:7890，留空保持现有配置）")
  CLAUDE_PROXY=$(proxy_input "$CLAUDE_PROXY" "Claude Code 代理 URL（示例 http://127.0.0.1:7890，留空保持现有配置）")
  if [[ -n "$CODEX_PROXY" || -n "$CLAUDE_PROXY" ]]; then
    AGENT_NO_PROXY=$(input "$AGENT_NO_PROXY" "NO_PROXY（Agent CLI 使用）")
  fi
fi

[[ -n "$CODEX_PROXY" ]] && ok "Codex 代理已配置"
[[ -n "$CLAUDE_PROXY" ]] && ok "Claude Code 代理已配置"
[[ -z "$CODEX_PROXY" && -z "$CLAUDE_PROXY" ]] && info "未配置 Agent 代理"

# ── Step 6: 写入 Agent 路径配置 ───────────────────────────────────────────────
step "写入配置"

DEFAULT_AGENT="claude"
[[ -z "$CLAUDE_BIN" && -n "$CODEX_BIN" ]] && DEFAULT_AGENT="codex"

ENV_FILE="$SCRIPT_DIR/.env"
cat > "$ENV_FILE" << EOF
# RemoteCC 环境配置（由 install.sh 生成 $(date '+%Y-%m-%d %H:%M')）
RC_USER=${RC_USER}
RC_PASS=${RC_PASS}
PORT=${PORT}
RCC_AGENT=${DEFAULT_AGENT}
CLAUDE_BIN=${CLAUDE_BIN}
CODEX_BIN=${CODEX_BIN}
CLAUDE_PROXY=${CLAUDE_PROXY}
CODEX_PROXY=${CODEX_PROXY}
AGENT_NO_PROXY=${AGENT_NO_PROXY}
${IS_SANDBOX_FLAG:+IS_SANDBOX=1}
EOF
chmod 600 "$ENV_FILE"
ok ".env 已生成（权限 600）"

# ── Step 7: 安装依赖 ──────────────────────────────────────────────────────────
step "安装依赖"

echo -e "  ${GRAY}安装服务端依赖（含 node-pty 原生编译）...${R}"

if NODE_GYP_PYTHON="$(find_node_gyp_python)"; then
  export npm_config_python="$NODE_GYP_PYTHON"
  ok "node-gyp Python: $NODE_GYP_PYTHON ($("$NODE_GYP_PYTHON" --version 2>&1 | head -1))"
else
  warn "未找到 Python >= 3.8；如 node-pty 需要本机编译，npm install 可能失败"
fi

# node-gyp 编译原生模块时使用 ~/.cache/node-gyp/<ver>/include/node/common.gypi，
# 该缓存由 node-gyp 从 node 安装目录复制而来。
# 策略：
#   1. 清除旧缓存（避免缓存里残留的 gnu++20 干扰）
#   2. patch node 安装目录的 common.gypi（gcc<10 不支持 gnu++20，需改为 gnu++2a）
#   3. npm install（node-gyp 重建缓存时会复制 patch 后的版本，从而正常编译）
#   4. 还原 node 安装目录的 common.gypi
NODE_VER_FULL=$(node -e "process.stdout.write(process.version.slice(1))")
NODE_GYP_CACHE="$HOME/.cache/node-gyp/${NODE_VER_FULL}"
if [[ -d "$NODE_GYP_CACHE" ]]; then
  info "清除 node-gyp 旧缓存 $NODE_GYP_CACHE ..."
  rm -rf "$NODE_GYP_CACHE"
fi

COMMON_GYPI="$(node -e "process.stdout.write(require('path').join(process.execPath,'../../include/node/common.gypi'))")"
PATCHED=false
GPP_MAJOR=""
if [[ -n "${CXX:-}" ]]; then
  GPP_MAJOR=$("$CXX" -dumpversion 2>/dev/null | cut -d. -f1 || true)
elif command -v g++ &>/dev/null; then
  GPP_MAJOR=$(g++ -dumpversion 2>/dev/null | cut -d. -f1 || true)
fi

restore_common_gypi() {
  if [[ "$PATCHED" == "true" && -f "${COMMON_GYPI}.rcc_bak" ]]; then
    mv "${COMMON_GYPI}.rcc_bak" "$COMMON_GYPI"
  fi
}

patch_gypi_std() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -i 's/gnu++20/gnu++2a/g' "$file"
}

ensure_node_gyp_cache() {
  local node_gyp_js=""
  local p
  for p in \
    "$(npm root -g 2>/dev/null)/npm/node_modules/node-gyp/bin/node-gyp.js" \
    "$(dirname "$(dirname "$(command -v npm)")")/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js"; do
    if [[ -f "$p" ]]; then
      node_gyp_js="$p"
      break
    fi
  done
  [[ -n "$node_gyp_js" ]] || return 0
  node "$node_gyp_js" install --target="$NODE_VER_FULL" >/dev/null 2>&1 || return 0
}

if [[ -n "$GPP_MAJOR" && "$GPP_MAJOR" -lt 10 ]]; then
  if [[ -f "${COMMON_GYPI}.rcc_bak" ]]; then
    info "恢复上次安装遗留的 common.gypi 备份 ..."
    mv "${COMMON_GYPI}.rcc_bak" "$COMMON_GYPI"
  fi
  if [[ -f "$COMMON_GYPI" ]] && grep -q "gnu++20" "$COMMON_GYPI" 2>/dev/null; then
    info "gcc $GPP_MAJOR 不支持 gnu++20，临时 patch node 安装目录 common.gypi ..."
    cp "$COMMON_GYPI" "${COMMON_GYPI}.rcc_bak"
    patch_gypi_std "$COMMON_GYPI"
    PATCHED=true
  fi
  ensure_node_gyp_cache
  patch_gypi_std "$NODE_GYP_CACHE/include/node/common.gypi"
fi

trap restore_common_gypi EXIT
(cd "$SCRIPT_DIR/server" && npm install --loglevel=warn 2>&1 | tail -2)
restore_common_gypi
trap - EXIT

if ! node -e "require('$SCRIPT_DIR/server/node_modules/node-pty')" 2>/dev/null; then
  err "node-pty 编译失败。请确认 g++ 已安装：\n  CentOS: yum install gcc-c++\n  Ubuntu: apt install g++ build-essential"
fi
ok "服务端依赖完成"

echo -e "  ${GRAY}安装前端依赖...${R}"
(cd "$SCRIPT_DIR/client" && npm install --loglevel=warn 2>&1 | tail -2)
ok "前端依赖完成"

# ── Step 8: 构建前端 ──────────────────────────────────────────────────────────
step "构建前端"

(cd "$SCRIPT_DIR/client" && npm run build 2>&1 | tail -3)
ok "前端已构建 → client/dist/"

# ── Step 9: 安装命令行工具 ────────────────────────────────────────────────────
step "安装命令行工具"

BIN_DIR="/usr/local/bin"
for tool in remotecc rcc-tui rcc-server; do
  src="$SCRIPT_DIR/$tool"
  [[ -f "$src" ]] || continue
  chmod +x "$src"
  if ln -sf "$src" "$BIN_DIR/$tool" 2>/dev/null; then
    ok "$tool → $BIN_DIR/$tool"
  else
    warn "无法写入 $BIN_DIR，跳过 $tool（可手动 ln -s $src $BIN_DIR/$tool）"
  fi
done

# 更新 rcc-server 脚本里的项目路径
sed -i "s|RCC_DIR=\"/paddle/project/local_tools/remote_cc\"|RCC_DIR=\"$SCRIPT_DIR\"|g" \
  "$SCRIPT_DIR/rcc-server" 2>/dev/null || true

# ── Step 10: 启动服务 ─────────────────────────────────────────────────────────
step "启动服务"

if [[ "$NON_INTERACTIVE" == "1" && "$_YES" == "1" ]] || confirm "y" "现在启动 RemoteCC 服务?"; then
  # 用 rcc-server stop 正确停止 watchdog + node（同时清 pid 文件）
  bash "$SCRIPT_DIR/rcc-server" stop 2>/dev/null || true
  # 额外等待 node 进程彻底消失，防止 lock 文件残留
  for _i in $(seq 1 15); do
    pgrep -f "node.*index.js" &>/dev/null || break; sleep 0.3
  done
  rm -f "$HOME/.rcc/local.token" "$HOME/.rcc/server.lock"

  # 通过 rcc-server start 启动（带 watchdog，读取 .env 配置）
  bash "$SCRIPT_DIR/rcc-server" start

  # 以 local.token 出现作为"服务就绪"的判断依据，等待最多 5s
  for _i in $(seq 1 10); do
    sleep 0.5
    [[ -f "$HOME/.rcc/local.token" ]] && break
  done

  if [[ -f "$HOME/.rcc/local.token" ]]; then
    ok "服务已启动（端口 $PORT）"
  else
    err "服务启动失败，查看日志: cat /tmp/rcc.log"
  fi
fi

# ── 完成提示 ──────────────────────────────────────────────────────────────────
IFACE_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' \
  || hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_IP")

echo ""
echo -e "  ${D}${HR}${R}"
echo -e "\n  ${GREEN}${B}✓ 部署完成！${R}\n"
echo -e "  ${B}Web 访问${R}"
echo -e "    本机:    ${CYAN}http://localhost:${PORT}${R}"
echo -e "    局域网:  ${CYAN}http://${IFACE_IP}:${PORT}${R}"
echo ""
echo -e "  ${B}账号${R}  ${RC_USER} / ${D}(已配置)${R}"
echo ""
echo -e "  ${B}常用命令${R}"
echo -e "    ${CYAN}remotecc start${R}    启动服务"
echo -e "    ${CYAN}remotecc stop${R}     停止服务"
echo -e "    ${CYAN}remotecc status${R}   服务状态"
echo -e "    ${CYAN}remotecc ls${R}       查看会话"
echo -e "    ${CYAN}rcc-tui${R}      交互式 TUI"
echo ""
echo -e "  ${D}${HR}${R}\n"
