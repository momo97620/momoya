#!/bin/bash

# 配置
IMAGE_NAME="debian:11"  # 使用的 Docker 镜像
CONTAINER_NAME="test_container"  # 容器名称
USER_COMMAND=""  # 用户输入的命令

# 检查 Docker 是否已安装
function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "错误: Docker 未安装，请先安装 Docker。"
        exit 1
    fi
}

# 获取用户输入的命令
function get_user_command() {
    echo "请输入要测试的命令（例如：curl -sS -O https://wutongli.de/wtl.sh && chmod +x wtl.sh && ./wtl.sh）："
    read -r USER_COMMAND
    if [[ -z "$USER_COMMAND" ]]; then
        echo "错误: 您没有输入命令！"
        exit 1
    fi
}

# 在容器中运行用户输入的命令
function run_container() {
    echo "启动 Docker 容器并测试命令..."

    docker run -it --name "$CONTAINER_NAME" "$IMAGE_NAME" bash -c "
        echo '正在设置测试环境...';
        apt-get update && apt-get install -y curl expect;

        echo '开始执行用户命令...';

        # 执行用户输入的命令
        $USER_COMMAND
    "
}

# 主流程
function main() {
    echo "==== Docker 快速测试环境 ===="
    check_docker
    get_user_command
    run_container
    echo "测试完成，环境已自动清理！"
}

# 执行主流程
main