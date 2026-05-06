#!/bin/bash
# 多角度证明本 demo 真的没有用 jpg/png 存储页图
# 用法:bash tools/verify-no-jpg.sh [REMOTE_HOST]
# 默认连 159.203.0.28,改第一个参数到自己服务器

set -uo pipefail

REMOTE_HOST="${1:-159.203.0.28}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/server1}"
PORT_PHP=8091
PORT_JAVA=8092

OK="✅"; FAIL="❌"; WARN="⚠️"
PASS=0; ISSUES=0

echo "========================================================"
echo "  存储证明:确认两个 demo 容器不含/不返回任何 jpg 页图"
echo "  目标服务器:$REMOTE_HOST"
echo "========================================================"
echo

# ─── 证明 1:容器内无 50KB+ jpg/png 文件 ───
echo "▼ 证明 1:容器内文件系统扫描(50KB+ 图)"
for c in magazine-php-demo magazine-java-demo; do
  RESULT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$REMOTE_HOST" \
    "docker exec $c find / -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) -size +50k 2>/dev/null" \
    | grep -v -E "node_modules|\.git" || true)
  if [ -z "$RESULT" ]; then
    echo "  $OK $c: 无任何 50KB+ jpg/png"
    PASS=$((PASS+1))
  else
    echo "  $FAIL $c: 找到大 jpg/png:"
    echo "$RESULT" | sed 's/^/      /'
    ISSUES=$((ISSUES+1))
  fi
done
echo

# ─── 证明 2:Docker image 大小 ───
echo "▼ 证明 2:Docker image 大小(应 200-400 MB,主要是 PDF 60 MB + 框架)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$REMOTE_HOST" \
  "docker images --format '{{.Repository}}\t{{.Size}}' | grep -E 'magazine-(php|java)-demo'" \
  | sed 's/^/  /'
echo

# ─── 证明 3:浏览器侧 — Range request 返回 206 ───
echo "▼ 证明 3:HTTP Range request 工作正常(206 Partial Content)"
for port in $PORT_PHP $PORT_JAVA; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Range: bytes=0-65535" \
    "http://$REMOTE_HOST:$port/pdf/chuanmei_2026_02.pdf" || echo "0")
  if [ "$STATUS" = "206" ]; then
    echo "  $OK :$port → 206 Partial Content"
    PASS=$((PASS+1))
  else
    echo "  $FAIL :$port → $STATUS(应是 206;若是 200 说明 Range 没工作)"
    ISSUES=$((ISSUES+1))
  fi
done
echo

# ─── 证明 4:页图 jpg 路由 — 应该都 404(不存在 jpg)───
echo "▼ 证明 4:页图 jpg URL 应该 404(因为压根没生成)"
for port in $PORT_PHP $PORT_JAVA; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://$REMOTE_HOST:$port/pages/page_001.jpg" || echo "0")
  if [ "$STATUS" = "404" ]; then
    echo "  $OK :$port /pages/page_001.jpg → 404(不存在 ✓)"
    PASS=$((PASS+1))
  else
    echo "  $FAIL :$port /pages/page_001.jpg → $STATUS(应该 404)"
    ISSUES=$((ISSUES+1))
  fi
done
echo

# ─── 证明 5:容器内 public/pdf 目录 大小 ───
echo "▼ 证明 5:容器内 PDF 目录大小(应 ≈ 60 MB,仅 1 个 PDF)"
for c in magazine-php-demo magazine-java-demo; do
  case $c in
    magazine-php-demo)  PDF_DIR="/app/public/pdf" ;;
    magazine-java-demo) PDF_DIR="/app/BOOT-INF/classes/pdf" ;;  # Spring Boot jar 内
  esac

  if [ "$c" = "magazine-java-demo" ]; then
    # Java 在 jar 内,看 jar 大小
    SIZE=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$REMOTE_HOST" \
      "docker exec $c ls -la /app/app.jar 2>/dev/null | awk '{print \$5}'" || echo "?")
    SIZE_MB=$((SIZE / 1024 / 1024))
    echo "  $c: app.jar = ${SIZE_MB} MB(包含 PDF + 框架)"
  else
    SIZE=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$REMOTE_HOST" \
      "docker exec $c du -sh $PDF_DIR 2>/dev/null | awk '{print \$1}'" || echo "?")
    echo "  $c: $PDF_DIR = $SIZE"
  fi
done
echo

# ─── 总结 ───
echo "========================================================"
if [ $ISSUES -eq 0 ]; then
  echo "  $OK 总结:$PASS 项验证通过,无任何额外 jpg 存储"
else
  echo "  $FAIL 总结:$PASS 项通过,$ISSUES 项失败 — 检查上面"
  exit 1
fi
echo "========================================================"
