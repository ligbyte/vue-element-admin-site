#!/usr/bin/env bash
#
# vue-element-admin-site 一键启动脚本 (macOS / Linux / Git Bash)
# 用法： ./start.sh [端口]        默认 8080，被占用时自动顺延
#        NO_OPEN=1 ./start.sh    不自动打开浏览器
#
set -u

# ---------- 切换到脚本所在目录 ----------
cd "$(dirname "$0")" || {
  echo "[错误] 无法进入项目目录"
  exit 1
}

PORT="${1:-8080}"
NO_OPEN="${NO_OPEN:-0}"
BASE="/vue-element-admin-site/"

echo "=========================================================="
echo "  vue-element-admin-site 一键启动 (VuePress 文档站)"
echo "=========================================================="
echo

# ---------- 1. 环境检查 ----------
if ! command -v node >/dev/null 2>&1; then
  echo "[错误] 未检测到 Node.js，请先安装 LTS 版本：https://nodejs.org/"
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "[错误] 未检测到 npm，请重新安装 Node.js 并确保 npm 已加入 PATH"
  exit 1
fi

case "${PORT}" in
  ''|*[!0-9]*)
    echo "[错误] 端口参数必须是数字，例如：./start.sh 8081"
    exit 1
    ;;
esac

NODE_VER="$(node -p 'process.versions.node')"
NODE_MAJOR="${NODE_VER%%.*}"
echo "[信息] Node.js 版本：v${NODE_VER}"

# ---------- 2. Node 17+ 兼容处理 ----------
# vuepress@0.14 / webpack 3 编译期使用 MD4 哈希，Node 17+ 的 OpenSSL 3
# 默认禁用 MD4（ERR_OSSL_EVP_UNSUPPORTED），冷启动编译会直接失败。
if [ "${NODE_MAJOR}" -ge 17 ] 2>/dev/null; then
  export NODE_OPTIONS="--openssl-legacy-provider ${NODE_OPTIONS:-}"
  echo "[信息] 检测到 Node 17+，已启用 --openssl-legacy-provider 兼容模式"
fi

# ---------- 3. 依赖安装 ----------
if [ ! -f "node_modules/vuepress/package.json" ]; then
  echo "[信息] 未检测到依赖，正在执行 npm install（首次较慢，请耐心等待）..."
  echo
  if ! npm install; then
    echo
    echo "[错误] npm install 执行失败，请检查网络或 npm 镜像配置"
    echo "       可尝试：npm config set registry https://registry.npmmirror.com"
    exit 1
  fi
  echo
  echo "[信息] 依赖安装完成"
else
  echo "[信息] 依赖已就绪，跳过安装"
fi

# ---------- 4. 端口可用性探测 ----------
# VuePress 会占用 port 与 port+1 两个端口（后者给 ws 用），
# 且端口被占用时会自行换端口，导致提示地址与实际不符；
# 这里先用 node 试监听，确认一对端口空闲后再启动，保证地址一致。
is_port_pair_free() {
  node -e '
    var net = require("net");
    var host = process.platform === "win32" ? "::1" : undefined;
    function probe(p) {
      return new Promise(function (res) {
        var s = net.createServer();
        s.once("error", function () { res(false) });
        s.listen(p, host, function () { s.close(function () { res(true) }) });
      });
    }
    var base = +process.argv[1];
    Promise.all([probe(base), probe(base + 1)]).then(function (r) {
      process.exit(r[0] && r[1] ? 0 : 1);
    });
  ' "$1" >/dev/null 2>&1
}

TRIES=0
while ! is_port_pair_free "${PORT}"; do
  echo "[警告] 端口 ${PORT} 已被占用，尝试 $((PORT + 1)) ..."
  PORT=$((PORT + 1))
  TRIES=$((TRIES + 1))
  if [ "${TRIES}" -ge 20 ]; then
    echo "[错误] 连续 20 个端口均被占用，请手动指定：./start.sh 9000"
    exit 1
  fi
done

SITE_URL="http://localhost:${PORT}${BASE}"

# ---------- 5. 自动打开浏览器（后台轮询，服务就绪后再打开） ----------
open_browser() {
  local url="$1" i
  for i in $(seq 1 120); do
    if command -v curl >/dev/null 2>&1; then
      curl -s --noproxy '*' -o /dev/null --max-time 2 "$url" && break
      sleep 1
    else
      sleep 5
      break
    fi
  done
  if command -v open >/dev/null 2>&1; then
    open "$url"                            # macOS
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1        # Linux
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$url"             # Git Bash (Windows)
  else
    echo "[提示] 请手动在浏览器打开：${url}"
  fi
}

echo
echo "[信息] 本地地址：${SITE_URL}"
echo "[信息] 首次编译约需 10-20 秒，编译完成后浏览器会自动打开"
echo "[提示] 停止服务请按 Ctrl+C"
echo
echo "----------------------------------------------------------"
echo

if [ "${NO_OPEN}" != "1" ]; then
  open_browser "${SITE_URL}" &
fi

# ---------- 6. 启动开发服务（前台运行） ----------
npm run dev -- -p "${PORT}"
EXIT_CODE=$?

echo
echo "----------------------------------------------------------"
if [ "${EXIT_CODE}" -ne 0 ] && [ "${EXIT_CODE}" -ne 130 ]; then
  echo "[错误] 服务异常退出，退出码：${EXIT_CODE}"
  echo "[排查] 1) 执行 npm install 重装依赖"
  echo "       2) 检查是否有其他 Node 进程占用端口 ${PORT}"
  echo "       3) 删除 node_modules/.cache 后重试"
else
  echo "[信息] 开发服务已停止"
fi
exit "${EXIT_CODE}"
