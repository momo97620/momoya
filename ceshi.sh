#!/bin/bash

# 配置
IMAGE_NAME="debian:11"  # 使用的 Docker 镜像
CONTAINER_NAME="test_container"  # 容器名称
SCRIPT_URL=""  # 待测试的脚本链接
SCRIPT_NAME="test_script.sh"  # 脚本文件名

# 检查 Docker 是否已安装
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

# 在容器中运行脚本并模拟用户输入
function run_container() {
    echo "启动 Docker 容器并测试脚本..."

    docker run -it --name "$CONTAINER_NAME" "$IMAGE_NAME" bash -c "
        echo '正在设置测试环境...';
        apt-get update && apt-get install -y curl expect;

        echo '下载脚本...';
        curl -sSL '$SCRIPT_URL' -o /tmp/$SCRIPT_NAME || { echo '脚本下载失败！'; exit 1; }

        echo '检查下载的脚本内容...';
        cat /tmp/$SCRIPT_NAME;

        echo '开始执行脚本...';

        # 执行脚本
        bash /tmp/$SCRIPT_NAME
    "
}

# 主流程
function main() {
    echo "==== Docker 快速测试环境 ===="
    check_docker
    get_script_url
    run_container
    echo "测试完成，您可以手动清理容器。"
}

# 执行主流程
main