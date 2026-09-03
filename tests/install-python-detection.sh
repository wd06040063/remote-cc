#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

WORKDIR="$TMP_ROOT/workdir"
FAKE_BIN="$TMP_ROOT/fake-bin"
HOME_DIR="$TMP_ROOT/home"
TOOLS_DIR="$TMP_ROOT/tools"
COMMON_GYPI="$TMP_ROOT/include/node/common.gypi"
NPM_ROOT="$TMP_ROOT/npm-root"

mkdir -p \
  "$WORKDIR/server/node_modules/node-pty" \
  "$WORKDIR/client" \
  "$FAKE_BIN" \
  "$HOME_DIR/.rcc" \
  "$(dirname "$COMMON_GYPI")" \
  "$NPM_ROOT/npm/node_modules/node-gyp/bin" \
  "$TOOLS_DIR/Python-3.10.8/bin" \
  "$TOOLS_DIR/gcc-8.2/bin" \
  "$TOOLS_DIR/gcc-12/bin"

cp "$ROOT/install.sh" "$WORKDIR/install.sh"
chmod +x "$WORKDIR/install.sh"

cat > "$WORKDIR/rcc-server" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "start" ]]; then
  mkdir -p "$HOME/.rcc"
  touch "$HOME/.rcc/local.token"
fi
exit 0
SCRIPT
chmod +x "$WORKDIR/rcc-server"

cat > "$TOOLS_DIR/Python-3.10.8/bin/python3.10" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "Python 3.10.8" ;;
  -c) exit 0 ;;
  *) exit 0 ;;
esac
SCRIPT
chmod +x "$TOOLS_DIR/Python-3.10.8/bin/python3.10"

cat > "$FAKE_BIN/python" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "Python 2.7.5" ;;
  -c) exit 1 ;;
  *) exit 1 ;;
esac
SCRIPT
chmod +x "$FAKE_BIN/python"

cat > "$FAKE_BIN/python3" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "Python 3.6.8" ;;
  -c) exit 1 ;;
  *) exit 1 ;;
esac
SCRIPT
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/node" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "v22.22.3"
    ;;
  -e)
    code="${2:-}"
    if [[ "$code" == *"process.version.slice(1)"* ]]; then
      printf "22.22.3"
    elif [[ "$code" == *"common.gypi"* ]]; then
      printf "%s" "$TEST_COMMON_GYPI"
    elif [[ "$code" == *"node-pty"* ]]; then
      exit 0
    else
      echo "unexpected node -e: $code" >&2
      exit 3
    fi
    ;;
  *)
    if [[ "${1:-}" == *"node-gyp.js" ]]; then
      exit 0
    fi
    echo "unexpected node invocation: $*" >&2
    exit 3
    ;;
esac
SCRIPT
chmod +x "$FAKE_BIN/node"

cat > "$FAKE_BIN/npm" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    echo "10.9.8"
    ;;
  root)
    if [[ "${2:-}" == "-g" ]]; then
      printf "%s" "$TEST_NPM_ROOT"
    else
      exit 2
    fi
    ;;
  install)
    if [[ "$(pwd)" == */server ]]; then
      if [[ -z "${npm_config_python:-}" ]]; then
        echo "missing npm_config_python for server npm install" >&2
        exit 42
      fi
      "$npm_config_python" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)'
      if [[ -z "${CXX:-}" || "$CXX" != *"/gcc-8.2/bin/g++" ]]; then
        echo "missing modern CXX for server npm install: ${CXX:-}" >&2
        exit 44
      fi
      if [[ -z "${CC:-}" || "$CC" != *"/gcc-8.2/bin/gcc" ]]; then
        echo "missing modern CC for server npm install: ${CC:-}" >&2
        exit 45
      fi
      if [[ "${LDFLAGS:-}" != *"-static-libstdc++"* || "${LDFLAGS:-}" != *"-static-libgcc"* ]]; then
        echo "missing static libstdc++/libgcc LDFLAGS: ${LDFLAGS:-}" >&2
        exit 46
      fi
    fi
    echo "fake install ok"
    ;;
  run)
    if [[ "${2:-}" == "build" ]]; then
      mkdir -p dist
      echo "fake build ok"
    else
      exit 2
    fi
    ;;
  *)
    echo "unexpected npm invocation: $*" >&2
    exit 2
    ;;
esac
SCRIPT
chmod +x "$FAKE_BIN/npm"

cat > "$FAKE_BIN/g++" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpversion|-dumpfullversion) echo "4.8.5" ;;
  --version) echo "g++ 4.8.5" ;;
  *) echo "g++ 4.8.5" ;;
esac
SCRIPT
chmod +x "$FAKE_BIN/g++"

cat > "$TOOLS_DIR/gcc-8.2/bin/g++" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpversion|-dumpfullversion) echo "8.2.0" ;;
  --version) echo "g++ 8.2.0" ;;
  *) echo "g++ 8.2.0" ;;
esac
SCRIPT
chmod +x "$TOOLS_DIR/gcc-8.2/bin/g++"

cat > "$TOOLS_DIR/gcc-8.2/bin/gcc" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpversion|-dumpfullversion) echo "8.2.0" ;;
  --version) echo "gcc 8.2.0" ;;
  *) echo "gcc 8.2.0" ;;
esac
SCRIPT
chmod +x "$TOOLS_DIR/gcc-8.2/bin/gcc"

cat > "$TOOLS_DIR/gcc-12/bin/g++" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpversion|-dumpfullversion) echo "12.3.0" ;;
  --version) echo "g++ 12.3.0" ;;
  *) echo "g++ 12.3.0" ;;
esac
SCRIPT
chmod +x "$TOOLS_DIR/gcc-12/bin/g++"

cat > "$TOOLS_DIR/gcc-12/bin/gcc" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
  -dumpversion|-dumpfullversion) echo "12.3.0" ;;
  --version) echo "gcc 12.3.0" ;;
  *) echo "gcc 12.3.0" ;;
esac
SCRIPT
chmod +x "$TOOLS_DIR/gcc-12/bin/gcc"

cat > "$FAKE_BIN/codex" <<'SCRIPT'
#!/usr/bin/env bash
echo "codex-test"
SCRIPT
chmod +x "$FAKE_BIN/codex"

touch "$COMMON_GYPI"

PATH="$FAKE_BIN:/usr/bin:/bin" \
HOME="$HOME_DIR" \
TEST_COMMON_GYPI="$COMMON_GYPI" \
TEST_NPM_ROOT="$NPM_ROOT" \
PYTHON_SEARCH_DIRS="$TOOLS_DIR" \
COMPILER_SEARCH_DIRS="$TOOLS_DIR" \
bash "$WORKDIR/install.sh" -u admin -p admin -y
