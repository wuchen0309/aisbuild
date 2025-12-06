#!/bin/bash

# --- 配置 ---
CONTAINER_NAME="aisbuild"
IMAGE_NAME="ghcr.io/wuchen0309/aisbuild:latest"
HOST_PORT="7860"
ENV_FILE="app.env"
PROXY_URL=""  # 如需代理请在此填入，例如 http://127.0.0.1:7890

# --- 环境检查 ---
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ 错误: 环境文件 '$ENV_FILE' 不存在！"
    exit 1
fi

echo "🚀 开始部署: $CONTAINER_NAME"

# --- 更新镜像与清理旧容器 ---
echo "--> 拉取镜像并清理旧容器..."
docker pull $IMAGE_NAME || { echo "❌ 镜像拉取失败"; exit 1; }
docker stop $CONTAINER_NAME > /dev/null 2>&1
docker rm $CONTAINER_NAME > /dev/null 2>&1

# --- 构建启动参数 ---
declare -a DOCKER_OPTS
DOCKER_OPTS=(
    -d
    --name "$CONTAINER_NAME"
    -p "${HOST_PORT}:7860"
    --env-file "$ENV_FILE"
    --restart unless-stopped
)

# 挂载 auth 目录（如果存在）
if [ -d "./auth" ]; then
    echo "--> 挂载 ./auth 目录 (并修正权限 1000:1000)"
    sudo chown -R 1000:1000 ./auth
    DOCKER_OPTS+=(-v "$(pwd)/auth:/app/auth")
fi

# 配置代理（如果设置）
if [ -n "$PROXY_URL" ]; then
    echo "--> 启用代理: $PROXY_URL"
    DOCKER_OPTS+=(-e "HTTP_PROXY=${PROXY_URL}" -e "HTTPS_PROXY=${PROXY_URL}")
fi

# --- 启动容器 ---
echo "--> 启动新容器..."
docker run "${DOCKER_OPTS[@]}" "$IMAGE_NAME"

# --- 清理无用镜像 ---
docker image prune -f > /dev/null 2>&1

# --- 🔥 自动放行防火墙端口 ---
echo "--> 检查防火墙设置..."
if command -v ufw > /dev/null; then
    # Ubuntu/Debian 使用 UFW
    if ! sudo ufw status | grep -q "$HOST_PORT"; then
        echo "   检测到 UFW，正在放行端口 $HOST_PORT..."
        sudo ufw allow "$HOST_PORT"/tcp
    fi
elif command -v firewall-cmd > /dev/null; then
    # CentOS/RHEL 使用 Firewalld
    if ! sudo firewall-cmd --list-ports | grep -q "$HOST_PORT/tcp"; then
        echo "   检测到 Firewalld，正在放行端口 $HOST_PORT..."
        sudo firewall-cmd --zone=public --add-port="$HOST_PORT"/tcp --permanent > /dev/null
        sudo firewall-cmd --reload > /dev/null
    fi
else
    echo "   ⚠️ 未检测到常用防火墙(UFW/Firewalld)，请手动确保端口 $HOST_PORT 已开放。"
fi

# --- 状态检查与输出 ---
echo "--> 等待服务启动..."
sleep 5

# 获取公网 IP
PUBLIC_IP=$(curl -s -4 --connect-timeout 3 ifconfig.me)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP="127.0.0.1"

echo ""
echo "✅ 部署完成！"
echo "🌐 访问地址: http://${PUBLIC_IP}:${HOST_PORT}"
echo "📝 查看日志: docker logs -f $CONTAINER_NAME"