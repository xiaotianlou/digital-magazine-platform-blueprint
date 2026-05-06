#!/bin/bash
# 一键部署到 159.203.0.28 (jobp 服务器)
# 用法:bash deploy/setup-on-jobp.sh
set -euo pipefail

REMOTE_USER=root
REMOTE_HOST=159.203.0.28
REMOTE_DIR=/opt/magazine-blueprint
SSH_KEY=~/.ssh/server1

echo "=== [1/4] 上传仓库到服务器 ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
  "mkdir -p $REMOTE_DIR && rm -rf $REMOTE_DIR/* $REMOTE_DIR/.* 2>/dev/null || true"

# rsync 整个仓库(排除 .git + node_modules + target)
rsync -av -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='target' \
  --exclude='vendor' \
  ../  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

echo "=== [2/4] docker compose build + up ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" bash <<EOF
set -euo pipefail
cd $REMOTE_DIR/deploy
docker compose down 2>/dev/null || true
docker compose build --pull
docker compose up -d
EOF

echo "=== [3/3] 健康检查 (直连端口,不走 nginx)==="
sleep 8

for i in 1 2 3 4 5; do
  PHP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$REMOTE_HOST:8091/" || echo 0)
  JAVA_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$REMOTE_HOST:8092/" || echo 0)
  echo "  attempt $i: PHP=$PHP_CODE JAVA=$JAVA_CODE"
  [ "$PHP_CODE" = "200" ] && [ "$JAVA_CODE" = "200" ] && break
  sleep 6
done

echo
echo "=== 部署完成 ==="
echo "PHP demo:  http://$REMOTE_HOST:8091/"
echo "Java demo: http://$REMOTE_HOST:8092/"
echo
echo "排错: ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST 'cd $REMOTE_DIR/deploy && docker compose logs -f'"
