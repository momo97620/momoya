#!/bin/bash

# 快速启动 Docker 测试环境（支持脚本链接）

# 配置
IMAGE_NAME="debian:11"  # 使用的 Docker 镜像
SCRIPT_URL=""           # 脚本链接
CONTAINER_NAME="test_container"

# 检查 Docker 是否安装
function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "错误: Docker 未安装，请先安装 Docker。"
        exit 1
    fi
}

# 获取用户输入的脚本链接
function get_script_url() {
    echo "请输入要测试的脚本链接（URL）："
    read -r SCRIPT_URL
    if [[ ! "$SCRIPT_URL" =~ ^https?:// ]]; then
        echo "错误: 无效的链接，请输入以 http:// 或 https:// 开头的 URL！"
        exit 1
    fi
}

# 运行测试容器
function run_container() {
    echo "启动干净的 Docker 测试环境..."
    docker run -it --rm --name "$CONTAINER_NAME" "$IMAGE_NAME" bash -c "
        echo '正在下载脚本...';
        apt-get update && apt-get install -y curl;
        curl -sSL '$SCRIPT_URL' -o /tmp/test_script.sh;
        chmod +x /tmp/test_script.sh;
        echo '开始执行脚本...';
        bash /tmp/test_script.sh
    "
}

# 主流程
function main() {
    echo "==== Docker 快速测试环境 ===="
    check_docker
    get_script_url
    run_container
    echo "测试完成，环境已自动清理！"
}

# 执行主流程
main