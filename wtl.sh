  #!/bin/bash

# 定义颜色
NC='\033[0m'              # 无颜色

set_shanghai_time() {
    # 检查当前时区
    CURRENT_TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
    
    # 如果时区不是上海时间，则设置为上海时间
    if [ "$CURRENT_TIMEZONE" != "Asia/Shanghai" ]; then
        timedatectl set-timezone Asia/Shanghai &> /dev/null
    fi

    # 启用网络时间同步
    timedatectl set-ntp true &> /dev/null
}

# 检查脚本是否有执行权限，如果没有则自动赋予权限
SCRIPT_PATH=$(readlink -f "$0")
if [ ! -x "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
fi

# 调用函数
set_shanghai_time
CACHE_DIR="/root/vps_cache"
CACHE_TTL=3600
mkdir -p "$CACHE_DIR" &>/dev/null

initialize_script() {
    {
        ulimit -n 65535

        echo 3 > /proc/sys/vm/drop_caches

        renice -n -5 $$ &>/dev/null
    } &>/dev/null
}

get_cache() {
    local cache_file="$CACHE_DIR/$1"
    local command="$2"

    {
        if [ -f "$cache_file" ]; then
            local cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
            if [ "$cache_age" -lt "$CACHE_TTL" ]; then
                cat "$cache_file"
                return
            fi
        fi

        eval "$command" > "$cache_file"
        cat "$cache_file"
    } &>/dev/null 
}

execute_script() {
    local script_url="$1"
    local success_message="$2"
    local script_name=$(basename "$script_url")
    local script_cache="$CACHE_DIR/$script_name"

    get_cache "$script_name" "curl -sSL $script_url -o $script_cache"
    bash "$script_cache" &>/dev/null
}

initialize_script &
        
echo "正在设置 m 指令快捷启动脚本..." > /dev/null 2>&1

target_script="/root/wtl.sh"

if [ ! -f "$target_script" ]; then
  echo "错误：主脚本文件未找到！路径：$target_script" > /dev/null 2>&1
  exit 1
fi

if [ ! -w "/usr/local/bin" ]; then
  echo "错误：需要管理员权限来创建符号链接。请使用 sudo 运行此脚本。" > /dev/null 2>&1
  exit 1
fi

if [ -L "/usr/local/bin/m" ] && [ "$(readlink /usr/local/bin/m)" == "$target_script" ]; then
  echo "m 指令已正确设置，无需重复设置。" > /dev/null 2>&1
else
  ln -sf "$target_script" /usr/local/bin/m > /dev/null 2>&1
  chmod +x "$target_script" > /dev/null 2>&1
  echo "成功设置 m 指令快捷启动脚本。现在可以通过 'm' 命令运行主脚本：$target_script" > /dev/null 2>&1
fi
install_script() {
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR" > /dev/null 2>&1
    fi
    
    cp "$SCRIPT_PATH" "$INSTALL_DIR" > /dev/null 2>&1
    chmod +x "$INSTALL_DIR/$(basename "$SCRIPT_PATH")" > /dev/null 2>&1
}
install_script &> /dev/null &
execute_script() {
    local script_url="$1"
    local success_message="$2"
    
    bash <(curl -sSL "$script_url")
    echo -e "${GREEN}$success_message${NC}"
    
    read -p "按任意键返回主菜单..."
}
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}Docker 已安装，跳过安装步骤。${NC}"
    else
        echo -e "${BLUE}正在安装 Docker 和 Docker Compose...${NC}"
        sudo curl -fsSL https://get.docker.com | bash && sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose && sudo systemctl start docker && sudo systemctl enable docker
        echo -e "${GREEN}Docker 和 Docker Compose 安装完成！${NC}"
    fi
    read -n 1 -s -r -p "按任意键返回..."
}


set_ip_priority() {
    # 检查当前用户是否为 root
    if [ "$EUID" -ne 0 ]; then
        echo "请以 root 用户运行此脚本！"
        exit 1
    fi

    # 检查当前优先级
    check_current_priority() {
        if [ -f /etc/gai.conf ]; then
            if grep -q "label ::ffff:0:0/96  2" /etc/gai.conf; then
                echo "当前优先级：IPv4 优先"
            elif grep -q "label ::/0  1" /etc/gai.conf; then
                echo "当前优先级：IPv6 优先"
            else
                echo "当前优先级：IPv4 和 IPv6 同时启用（默认）"
            fi
        else
            echo "当前优先级：IPv4 和 IPv6 同时启用（默认，/etc/gai.conf 文件不存在）"
        fi
    }

    # 设置优先级
    set_priority() {
        # 备份配置文件
        cp -n /etc/gai.conf /etc/gai.conf.bak 2>/dev/null

        # 清理已有配置
        sed -i '/precedence/d' /etc/gai.conf 2>/dev/null
        sed -i '/label/d' /etc/gai.conf 2>/dev/null

        case "$1" in
            1)
                echo "正在设置优先使用 IPv4..."
                echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
                echo "label ::ffff:0:0/96  2" >> /etc/gai.conf
                ;;
            2)
                echo "正在设置优先使用 IPv6..."
                echo "precedence ::/0  100" >> /etc/gai.conf
                echo "label ::/0  1" >> /etc/gai.conf
                ;;
            3)
                echo "正在设置同时启用 IPv4 和 IPv6..."
                rm -f /etc/gai.conf
                ;;
            *)
                echo "无效的选项！请输入 '1'、'2' 或 '3'。"
                exit 1
                ;;
        esac

        # 验证设置
        if [ "$1" -eq 3 ]; then
            if [ ! -f /etc/gai.conf ]; then
                echo "验证设置：/etc/gai.conf 文件已删除，恢复默认行为。"
            else
                echo "错误：/etc/gai.conf 文件未删除！"
                exit 1
            fi
        else
            echo "验证设置："
            cat /etc/gai.conf
        fi
    }

    # 显示菜单
    show_menu() {
        clear
        echo "==============================="
        echo " 设置 IPv4 或 IPv6 优先级"
        echo "==============================="
        check_current_priority
        echo "1. 优先使用 IPv4"
        echo "2. 优先使用 IPv6"
        echo "3. 同时启用 IPv4 和 IPv6"
        echo "==============================="
        read -p "请输入选项 [1/2/3]：" choice
        if ! [[ "$choice" =~ ^[123]$ ]]; then
            echo "无效的输入！请输入正确选项。"
            exit 1
        fi
        set_priority "$choice"
        echo "设置完成！按任意键退出..."
        read -n 1 -s -r
    }

    show_menu
}


update_script() {
    local remote_url="https://raw.githubusercontent.com/momo97620/momoya/refs/heads/main/wtl.sh"
    local local_path="/root/wtl.sh"  # 确保文件名是正确的

    echo -e "${YELLOW}正在更新脚本到最新版本...${NC}"

    if curl -s --head "$remote_url" | grep "200 OK" > /dev/null; then
        if curl -sSL "$remote_url" -o "$local_path"; then
            chmod +x "$local_path"
            echo -e "${GREEN}脚本更新成功！最新版本已保存到 $local_path。${NC}"

            echo -e "${YELLOW}正在执行更新后的脚本...${NC}"
            exec "$local_path"  # 使用 exec 替换当前进程
        else
            echo -e "${RED}脚本更新失败，请检查远程 URL 是否正确。${NC}"
        fi
    else
        echo -e "${RED}无法访问远程 URL，请检查网络连接或 URL 是否正确。${NC}"
    fi

    read -p "按任意键返回主菜单..."
}


set_ssh_keepalive() {
    local config_file="/etc/ssh/sshd_config"
    local interval=60
    local count=10

    echo "正在配置 SSH 客户端保持连接参数..."
    if [[ ! -f "$config_file" ]]; then
        echo "错误：SSH 配置文件 $config_file 不存在。" >&2
        exit 1
    fi

    read -p "是否确认修改 SSH 配置？(y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "取消修改。"
        exit 0
    fi

    read -p "请输入 ClientAliveInterval 值（默认 60）: " user_interval
    if [[ -n "$user_interval" ]]; then
        interval=$user_interval
    fi

    read -p "请输入 ClientAliveCountMax 值（默认 10）: " user_count
    if [[ -n "$user_count" ]]; then
        count=$user_count
    fi

    if grep -q '^#\?ClientAliveInterval' "$config_file"; then
        sed -ri "s/^#?.*ClientAliveInterval.*/ClientAliveInterval $interval/" "$config_file"
    else
        echo "ClientAliveInterval $interval" >> "$config_file"
    fi

    if grep -q '^#\?ClientAliveCountMax' "$config_file"; then
        sed -ri "s/^#?.*ClientAliveCountMax.*/ClientAliveCountMax $count/" "$config_file"
    else
        echo "ClientAliveCountMax $count" >> "$config_file"
    fi

    echo "重启 SSH 服务以应用更改..."
    sudo systemctl restart sshd
    if [[ $? -eq 0 ]]; then
        echo "SSH 配置已更新并成功应用！"
    else
        echo "SSH 服务重启失败，请检查配置。" >&2
        exit 1
    fi
    echo "按任意键返回主菜单..."
    read -n 1 -s -r
}
image_management() {
    while true; do
    clear
    echo -e "${BLUE}\n===== 镜像管理 =====${NC}"
    
    echo -e "${RED}1.${NC} ${BOLD_GREEN}列出所有镜像${NC}      ${RED}2.${NC} ${BOLD_GREEN}删除镜像${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}3.${NC} ${BOLD_GREEN}启动镜像${NC}          ${RED}4.${NC} ${BOLD_GREEN}停止镜像${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}5.${NC} ${BOLD_GREEN}启动所有镜像${NC}      ${RED}6.${NC} ${BOLD_GREEN}停止所有镜像${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}7.${NC} ${BOLD_GREEN}重启镜像${NC}          ${RED}0.${NC} ${BOLD_GREEN}返回主菜单${NC}"
    echo -e "---------------------------"  # 添加分隔线
    
    read -p "请选择操作: " image_choice  

        case $image_choice in
            1) 
                echo -e "${BLUE}当前镜像列表:${NC}"
                docker images
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            2) 
                images=($(docker images --format '{{.Repository}}:{{.Tag}}'))
                if [ ${#images[@]} -eq 0 ]; then
                    echo -e "${RED}没有找到任何镜像！${NC}"
                else
                    PS3="请输入对应的数字选择："
                    echo -e "${BLUE}请选择要删除的镜像（按回4返回）:${NC}"
                    select image in "${images[@]}" "返回"; do
                        if [ "$REPLY" == "0" ] || [ "$image" == "返回" ]; then
                            echo -e "${YELLOW}已取消操作，返回上级菜单。${NC}"
                            break
                        elif [[ " ${images[@]} " =~ " ${image} " ]]; then
                            docker rmi "$image" && echo -e "${GREEN}镜像 $image 已被删除！${NC}" || echo -e "${RED}删除失败，请检查镜像名称！${NC}"
                            break
                        else
                            echo -e "${RED}无效的选择，请重试！${NC}"
                        fi
                    done
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            3) 
                read -p "请输入要启动的镜像（按回车键返回）: " image_to_run
                docker run -d "$image_to_run" && echo -e "${GREEN}镜像 $image_to_run 已启动！${NC}" || echo -e "${RED}启动失败，请检查镜像名称！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            4) 
                running_images=$(docker ps --format '{{.ID}}: {{.Image}}')
                if [ -z "$running_images" ]; then
                    echo -e "${RED}没有运行中的镜像！${NC}"
                else
                    PS3="请输入对应的数字选择（按5返回）："
                    echo -e "${BLUE}请选择要停止的镜像:${NC}"
                    select image in $running_images "返回"; do
                        if [ "$REPLY" == "0" ] || [ "$image" == "返回" ]; then
                            echo -e "${YELLOW}已取消操作，返回上级菜单。${NC}"
                            break
                        elif [ -n "$image" ]; then
                            image_id=$(echo "$image" | cut -d':' -f1)
                            docker stop "$image_id" && echo -e "${GREEN}镜像 $image_id 已被停止！${NC}" || echo -e "${RED}停止失败！${NC}"
                            break
                        else
                            echo -e "${RED}无效的选择，请重试！${NC}"
                        fi
                    done
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            5) 
                echo -e "${BLUE}正在启动所有镜像...${NC}"
                for image in $(docker images --format '{{.Repository}}:{{.Tag}}'); do
                    docker run -d "$image"
                done
                echo -e "${GREEN}所有镜像已启动！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            6) 
                echo -e "${BLUE}正在停止所有镜像...${NC}"
                docker stop $(docker ps -q)
                echo -e "${GREEN}所有镜像已停止！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            7) 
                images=($(docker images --format '{{.Repository}}:{{.Tag}}'))
                if [ ${#images[@]} -eq 0 ]; then
                    echo -e "${RED}没有找到任何镜像！${NC}"
                else
                    PS3="请输入对应的数字选择（按回车键返回）："
                    echo -e "${BLUE}请选择要重启的镜像:${NC}"
                    select image in "${images[@]}" "返回"; do
                        if [ "$image" == "返回" ]; then
                            break
                        elif [[ " ${images[@]} " =~ " ${image} " ]]; then
                            image_id=$(docker ps -q --filter ancestor="$image")
                            if [ -n "$image_id" ]; then
                                docker restart "$image_id" && echo -e "${GREEN}镜像 $image 的容器已被重启！${NC}" || echo -e "${RED}重启失败！${NC}"
                            else
                                echo -e "${RED}没有运行中的镜像！${NC}"
                            fi
                            break
                        else
                            echo -e "${RED}无效的选择，请重试！${NC}"
                        fi
                    done
                fi
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            0) break ;;
            *) echo -e "${RED}无效的选择，请重试！${NC}" ;;
        esac
    done
}
declare -A RAINBOW_PROMPT

RAINBOW_PROMPT[RED]='\033[0;31m'
RAINBOW_PROMPT[GREEN]='\033[0;32m'
RAINBOW_PROMPT[YELLOW]='\033[0;33m'
RAINBOW_PROMPT[BLUE]='\033[0;34m'
RAINBOW_PROMPT[PURPLE]='\033[0;35m'
RAINBOW_PROMPT[CYAN]='\033[0;36m'
RAINBOW_PROMPT[WHITE]='\033[0;37m'
RAINBOW_PROMPT[RESET]='\033[0m'

RAINBOW_PROMPT[BACKUP_FILE]="$HOME/.bashrc.backup"
RAINBOW_PROMPT[BASHRC_FILE]="$HOME/.bashrc"

RAINBOW_PROMPT::print_message() {
    local color=$1
    local message=$2
    echo -e "${RAINBOW_PROMPT[$color]}$message${RAINBOW_PROMPT[RESET]}"
}

RAINBOW_PROMPT::show_menu() {
    clear
    echo "================================"
    echo "       VPS主机名颜色设置        "
    echo "================================"
    echo "1. 设置彩虹色主机名"
    echo "2. 恢复默认设置"
    echo "0. 返回菜单"
    echo "================================"
}

RAINBOW_PROMPT::create_backup() {
    if [ ! -f "${RAINBOW_PROMPT[BACKUP_FILE]}" ]; then
        cp "${RAINBOW_PROMPT[BASHRC_FILE]}" "${RAINBOW_PROMPT[BACKUP_FILE]}"
    fi
}

RAINBOW_PROMPT::press_any_key() {
    RAINBOW_PROMPT::print_message "YELLOW" "\n按任意键返回主菜单..."
    read -n 1 -s -r
}

RAINBOW_PROMPT::create_rainbow_prompt() {
    RAINBOW_PROMPT::create_backup
    
    sed -i '/^PS1=/d' "${RAINBOW_PROMPT[BASHRC_FILE]}"
    
    local rainbow_ps1="PS1=\""
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RED]}\\]r"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[GREEN]}\\]o"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[YELLOW]}\\]o"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[BLUE]}\\]t"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[PURPLE]}\\]@"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[CYAN]}\\]h"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RED]}\\]k"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[GREEN]}\\]g"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[YELLOW]}\\]1"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[BLUE]}\\]1"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[PURPLE]}\\]-"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[CYAN]}\\]2"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RED]}\\]0"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[GREEN]}\\]2"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[YELLOW]}\\]4"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[BLUE]}\\]1"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[PURPLE]}\\]0"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[CYAN]}\\]0"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RED]}\\]3"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[GREEN]}\\]1"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[YELLOW]}\\]3"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[BLUE]}\\]1"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[PURPLE]}\\]2"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[CYAN]}\\]0"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RED]}\\]4"
    rainbow_ps1+="\\[${RAINBOW_PROMPT[RESET]}\\]:\\w\\$ \""

    echo "$rainbow_ps1" >> "${RAINBOW_PROMPT[BASHRC_FILE]}"
    
    source "${RAINBOW_PROMPT[BASHRC_FILE]}"
    RAINBOW_PROMPT::print_message "GREEN" "\n彩虹效果已成功应用！"
}

RAINBOW_PROMPT::restore_default() {
    if [ -f "${RAINBOW_PROMPT[BACKUP_FILE]}" ]; then
        cp "${RAINBOW_PROMPT[BACKUP_FILE]}" "${RAINBOW_PROMPT[BASHRC_FILE]}"
        source "${RAINBOW_PROMPT[BASHRC_FILE]}"
        RAINBOW_PROMPT::print_message "GREEN" "\n已成功恢复默认设置！"
    else
        RAINBOW_PROMPT::print_message "RED" "\n未找到备份文件，无法恢复默认设置！"
    fi
}

RAINBOW_PROMPT::main() {
    while true; do
        RAINBOW_PROMPT::show_menu
        read -p "请输入选项 [1-3]: " choice
        
        case $choice in
            1)
                RAINBOW_PROMPT::print_message "CYAN" "\n正在设置彩虹色主机名..."
                RAINBOW_PROMPT::create_rainbow_prompt
                RAINBOW_PROMPT::press_any_key
                ;;
            2)
                RAINBOW_PROMPT::print_message "CYAN" "\n正在恢复默认设置..."
                RAINBOW_PROMPT::restore_default
                RAINBOW_PROMPT::press_any_key
                ;;
            0)
                echo "返回主菜单..."
                break
                ;;
            *)
                RAINBOW_PROMPT::print_message "RED" "\n无效的选项，请重新选择！"
                RAINBOW_PROMPT::press_any_key
                ;;
        esac
    done
}


BACKUP_DIR="$HOME/backup"  # 备份存储路径
BACKUP_SCRIPT="$HOME/backup.sh"  # 脚本自身路径

mkdir -p "$BACKUP_DIR"

perform_backup() {
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    echo "Stopping Docker..."
    systemctl stop docker

    BACKUP_FILE="$BACKUP_DIR/docker_backup_$TIMESTAMP.tar.gz"
    echo "Backing up Docker data to $BACKUP_FILE..."
    
    if tar czvf "$BACKUP_FILE" /var/lib/docker; then
        echo "Starting Docker..."
        systemctl start docker
        echo "Backup completed successfully!"
        echo "结果：成功" >> "$BACKUP_DIR/backup_log.txt"
    else
        echo "Backup failed!"
        echo "结果：失败 - 备份过程中发生错误" >> "$BACKUP_DIR/backup_log.txt"
    fi
}

setup_cron_job() {
    (crontab -l | grep -q "$BACKUP_SCRIPT") && {
        echo "定时任务已存在，跳过设置。"
        echo "结果：失败 - 定时任务已存在" >> "$BACKUP_DIR/backup_log.txt"
        return
    }

    (crontab -l 2>/dev/null; echo "0 5 */7 * * $BACKUP_SCRIPT >> $BACKUP_DIR/backup.log 2>&1") | crontab -
    echo "已设置定时任务：每 7 天凌晨 5 点自动备份。"
    echo "结果：成功" >> "$BACKUP_DIR/backup_log.txt"
}

restore_backup() {
    read -p "请输入备份文件名（例如 docker_backup_YYYYMMDDHHMMSS.tar.gz）： " BACKUP_FILE
    read -p "请输入新服务器的 IP 地址： " SERVER_IP

    echo "正在复制备份文件到新服务器..."
    if scp "$BACKUP_DIR/$BACKUP_FILE" user@"$SERVER_IP":/path/to/backup/; then
        echo "正在恢复备份..."
        ssh user@"$SERVER_IP" << EOF
            cd /path/to/backup/
            echo "解压备份文件..."
            if tar xzvf "$BACKUP_FILE"; then
                echo "停止 Docker 服务..."
                sudo systemctl stop docker
                echo "恢复 Docker 数据..."
                if sudo rsync -a --remove-source-files ./var/lib/docker/ /var/lib/docker/; then
                    echo "启动 Docker 服务..."
                    sudo systemctl start docker
                    echo "备份恢复完成！"
                    echo "结果：成功" >> "$BACKUP_DIR/backup_log.txt"
                else
                    echo "恢复 Docker 数据失败！"
                    echo "结果：失败 - 恢复过程中发生错误" >> "$BACKUP_DIR/backup_log.txt"
                fi
            else
                echo "解压备份文件失败！"
                echo "结果：失败 - 解压过程中发生错误" >> "$BACKUP_DIR/backup_log.txt"
            fi
EOF
    else
        echo "复制备份文件失败！"
        echo "结果：失败 - 复制过程中发生错误" >> "$BACKUP_DIR/backup_log.txt"
    fi
}

backup_menu() {
    while true; do
        echo "请选择操作："
        echo "1. 手动备份"
        echo "2. 自动备份（每7天一次）"
        echo "3. 恢复备份"
        echo "4. onedrive邮箱"
        echo "5. 返回主菜单"
        read -p "请输入选项 (1、2、3或4): " choice

        case $choice in
            1)
                echo "开始手动备份..."
                perform_backup
                ;;
            2)
                echo "开始自动备份..."
                setup_cron_job
                echo "请注意，自动备份将在每 7 天的凌晨 5 点执行。"
                ;;
            3)
                echo "开始恢复备份..."
                restore_backup
                ;;
            4)
                install_onedrive
                ;;
               
            5)
                echo "返回主菜单。"
                return
                ;;
            *)
                echo "无效选项，请选择1、2、3、4或5。"
                ;;
        esac

        read -p "按任意键返回备份菜单..." -n1 -s
        echo
    done
}

container_management() {
    while true; do
    clear
    echo -e "${BLUE}\n===== 容器管理 =====${NC}"
    
    # 第一排选项
    echo -e "${RED}1.${NC} ${BOLD_GREEN}列出所有容器${NC}      ${RED}2.${NC} ${BOLD_GREEN}启动容器${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}3.${NC} ${BOLD_GREEN}停止容器${NC}          ${RED}4.${NC} ${BOLD_GREEN}重启容器${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}5.${NC} ${BOLD_GREEN}删除容器${NC}          ${RED}6.${NC} ${BOLD_GREEN}查看容器日志${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}7.${NC} ${BOLD_GREEN}停止所有容器${NC}     ${RED}8.${NC} ${BOLD_GREEN}启动所有容器${NC}"
    echo -e "---------------------------"
    
    echo -e "${RED}0.${NC} ${BOLD_GREEN}返回主菜单${NC}"
    echo -e "---------------------------"  # 添加分隔线
    
    read -p "请选择操作: " container_choice
    
        case $container_choice in
            1) 
                echo -e "${BLUE}当前容器列表:${NC}"
                docker ps -a
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            2) 
                while true; do
                    read -p "请输入容器名称或ID（按回车键返回）： " container
                    if [ -z "$container" ]; then
                        echo -e "${YELLOW}已取消操作，返回上级菜单。${NC}"
                        break
                    fi
                    docker start "$container" && echo -e "${GREEN}容器 $container 已启动！${NC}" || echo -e "${RED}启动失败，请检查容器名称或ID！${NC}"
                done
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            3) 
                while true; do
                    containers=$(docker ps --format '{{.Names}}')
                    if [ -z "$containers" ]; then
                        echo -e "${RED}没有运行中的容器！${NC}"
                        break
                    fi
                    echo -e "${BLUE}运行中的容器（按回车键返回）:${NC}"
                    docker ps --format '容器名: {{.Names}}, 容器ID: {{.ID}}'
                    read -p "请输入容器名称或ID（按3返回）： " container
                    if [ -z "$container" ]; then
                        echo -e "${YELLOW}已取消操作，返回上级菜单。${NC}"
                        break
                    fi
                    docker stop "$container" && echo -e "${GREEN}容器 $container 已停止！${NC}" || echo -e "${RED}停止失败，请检查容器名称或ID！${NC}"
                done
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            4) 
                read -p "请输入容器名称或ID（按回车键返回）： " container
                docker restart "$container" && echo -e "${GREEN}容器 $container 已重启！${NC}" || echo -e "${RED}重启失败，请检查容器名称或ID！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            5) 
                containers=($(docker ps -a --format '{{.Names}}'))
if [ ${#containers[@]} -eq 0 ]; then
    echo -e "${RED}没有找到任何容器！${NC}"
else
    echo -e "${BLUE}请选择要删除的容器（输入3返回菜单）:${NC}"

    PS3="请输入对应的数字选择："
    select container in "${containers[@]}" "返回上级菜单"; do
        if [ "$REPLY" -eq 0 ] || [ "$REPLY" -eq $((${#containers[@]} + 1)) ]; then
            echo -e "${YELLOW}已返回上级菜单。${NC}"
            break
        elif [ -z "$container" ]; then
            echo -e "${RED}无效的选择，请重试！${NC}"
        elif [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -le $((${#containers[@]} + 1)) ]; then
            if [ "$REPLY" -le "${#containers[@]}" ]; then
                docker rm -f "$container" && echo -e "${GREEN}容器 $container 已被删除！${NC}" || echo -e "${RED}删除失败，请检查容器名称或ID！${NC}"
            fi
            break
        else
            echo -e "${RED}无效的选择，请重试！${NC}"
        fi
    done
fi
read -n 1 -s -r -p "按任意键返回..."
           ;;
            6) 
                read -p "请输入容器名称或ID（按回车键返回）： " container
                docker logs "$container" || echo -e "${RED}获取日志失败，请检查容器名称或ID！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            7) 
                echo -e "${BLUE}正在停止所有容器...${NC}"
                docker stop $(docker ps -q) && echo -e "${GREEN}所有容器已停止！${NC}" || echo -e "${RED}停止失败！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            8) 
                echo -e "${BLUE}正在启动所有容器...${NC}"
                docker start $(docker ps -aq) && echo -e "${GREEN}所有容器已启动！${NC}" || echo -e "${RED}启动失败！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
            0) 
                echo -e "${YELLOW}返回主菜单。${NC}"
                break
                ;;
            *) 
                echo -e "${RED}无效的选择，请重试！${NC}"
                read -n 1 -s -r -p "按任意键返回..."
                ;;
        esac
    done
}

install_onedrive() {
    echo "正在增加交换空间..."
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "交换空间已启用。"

    echo "正在安装必要的依赖项..."
    if ! sudo apt update; then
        echo "更新失败，请检查网络连接。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    if ! sudo apt install -y build-essential git wget curl libcurl4-openssl-dev libsqlite3-dev ldc; then
        echo "依赖项安装失败，请检查错误信息。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo "正在下载 OneDrive 客户端..."
    if ! wget https://github.com/abraunegg/onedrive/archive/refs/tags/v2.5.3.tar.gz; then
        echo "下载失败，请检查网络连接。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo "正在解压下载的文件..."
    if ! tar -xzvf v2.5.3.tar.gz; then
        echo "解压失败，请检查下载的文件。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    cd onedrive-2.5.3 || { echo "进入目录失败"; read -n 1 -s -r -p "按任意键返回..."; return; }

    echo "正在运行 ./configure..."
    if ! ./configure; then
        echo "./configure 失败，请检查错误信息。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo "正在编译 OneDrive..."
    if ! make -j1; then
        echo "编译失败，请检查错误信息。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo "正在安装 OneDrive..."
    if ! sudo make install; then
        echo "安装失败，请检查错误信息。"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi

    echo "OneDrive 安装完成。请运行 'onedrive' 进行初始配置。"
    echo "要启动 OneDrive，请使用 'onedrive --monitor'。"
    read -n 1 -s -r -p "按任意键返回..."
}


show_main_menu() {
    clear
    # 定义颜色
    LIGHTCYAN='\033[1;36m'  # 明亮的青色
    PINK='\033[38;5;198m'     # 深粉色
    NC='\033[0m'           # 重置颜色

    echo -e "${LIGHTCYAN}"
    echo " ██╗    ██╗██╗   ██╗████████╗ ██████╗ ███╗   ██╗ ██████╗ ██╗     ██╗"
    echo " ██║    ██║██║   ██║╚══██╔══╝██╔═══██╗████╗  ██║██╔════╝ ██║     ██║"
    echo " ██║ █╗ ██║██║   ██║   ██║   ██║   ██║██╔██╗ ██║██║  ███╗██║     ██║"
    echo " ██║███╗██║██║   ██║   ██║   ██║   ██║██║╚██╗██║██║   ██║██║     ██║"
    echo " ╚███╔███╔╝╚██████╔╝   ██║   ╚██████╔╝██║ ╚████║╚██████╔╝███████╗██║"
    echo "  ╚══╝╚══╝  ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝"
    echo -e "${NC}"

    echo -e "${LIGHTCYAN}============================= VPS 脚本菜单 =============================${NC}"
    echo -e "${LIGHTCYAN}使用快捷指令 m 可快速打开脚本😊${NC}"
    echo -e "${PINK}作者：梧桐里${NC}"
    echo -e "${LIGHTCYAN}=====================================================================${NC}"
    
    echo -e "${YELLOW}请选择要执行的任务：${NC}"

    echo -e "  ${BLUE}1.${NC} ${PINK}♥${NC} ${NC}节点合集 ▶${NC}      ${BLUE}09${NC} ${PINK}♥${NC} ${NC}系统信息查询${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}2.${NC} ${PINK}♥${NC} ${NC}UFW 防火墙${NC}      ${BLUE}10${NC} ${PINK}♥${NC} ${NC}IPv4/6优先${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}3.${NC} ${PINK}♥${NC} ${GREEN}改密钥登录${NC}      ${BLUE}11${NC} ${PINK}♥${NC} ${NC}更新主脚本${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}4.${NC} ${PINK}♥${NC} ${GREEN}改登录端口${NC}      ${BLUE}12${NC} ${PINK}♥${NC} ${YELLOW}保持ssh连接${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}5.${NC} ${PINK}♥${NC} ${GREEN}一键搭建节点${NC}    ${BLUE}13${NC} ${PINK}♥${NC} ${YELLOW}一键DD系统 ▶${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}6.${NC} ${PINK}♥${NC} ${GREEN}一键配置WARP${NC}    ${BLUE}14${NC} ${PINK}♥${NC} ${RED}监控TG关键词 ▶${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}7.${NC} ${PINK}♥${NC} ${GREEN}一键BBR加速     ${BLUE}15${NC} ${PINK}♥${NC} ${RED}主机名颜色${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}8.${NC} ${PINK}♥${NC} ${NC}Docker项目 ▶${NC}    ${BLUE}16${NC} ${PINK}♥${NC} ${RED}测试流媒体${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}17.${NC} ${PINK}♥${NC} ${YELLOW}一键反向代理${NC}"

echo "-------------------------------------"

echo -e "  ${BLUE}00${NC} ${PINK}♥${NC} ${RED}退出${NC}"

read -p "请输入选项 (0-18): " choice

  case "$choice" in
        1)
execute_script() {
    local url="$1"
    local message="$2"
    
    echo "正在执行: $message"
    wget -N --no-check-certificate "$url" -O temp_script.sh
    chmod +x temp_script.sh
    
    if [[ -f temp_script.sh && -x temp_script.sh ]]; then
        ./temp_script.sh
        read -p "脚本执行完毕，按任意键返回子菜单..."
    else
        echo "下载的脚本无法执行，请检查权限或下载链接。"
        
    fi
    
    rm -f temp_script.sh
}

while true; do
    clear_screen
    echo -e "\e[1;34m=========================\e[0m"
    echo -e "\e[1;32m  多协议节点搭建 + 流量转发  \e[0m"
    echo -e "\e[1;34m=========================\e[0m"
    echo -e "\e[1;30m1) Hy2搭建\e[0m"
    echo -e "\e[1;34m-----------------------\e[0m"
    echo -e "\e[1;30m2) 多协议搭建\e[0m"
    echo -e "\e[1;34m-----------------------\e[0m"
    echo -e "\e[1;30m3) realm2转发\e[0m"
    echo -e "\e[1;34m-----------------------\e[0m"
    echo -e "\e[1;30m0) 返回主菜单\e[0m"
    echo -e "\e[1;34m=========================\e[0m"

    read -p "输入选项 (0-3): " sub_choice

    case $sub_choice in
        1)
            clear_screen
            echo "正在下载并执行 Hy2 搭建脚本..."
            execute_script "https://raw.githubusercontent.com/flame1ce/hysteria2-install/main/hysteria2-install-main/hy2/hysteria.sh" "Hy2 搭建脚本"
            ;;
        2)
            clear_screen
            echo "正在下载并执行多协议搭建脚本..."
            execute_script "https://raw.githubusercontent.com/233boy/sing-box/main/install.sh" "多协议搭建脚本"
            ;;
        3)
            clear_screen
            echo "正在下载并执行 realm2 转发脚本..."
            execute_script "https://raw.githubusercontent.com/qqrrooty/EZrealm/main/realm.sh" "realm2 转发脚本"
            ;;
        0)
            echo "返回主菜单。"
            break
            ;;
        *)
            echo "无效选项，请重试。"
            read -p "按任意键继续..."
            ;;
    esac
done
           ;;
        2)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/ufw_script.log"


if [[ $EUID -ne 0 ]]; then
    echo "此脚本必须以root权限运行 (sudo)" 
    exit 1
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

hostnamectl set-hostname $(hostname -s)

if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}UFW 未安装，正在安装...${NC}"
    log "UFW 未安装，正在安装"
    if sudo apt install ufw -y; then
        echo -e "${GREEN}UFW 安装成功！${NC}"
        log "UFW 安装成功"
    else
        echo -e "${RED}UFW 安装失败，请检查网络或源配置！${NC}"
        log "UFW 安装失败"
        exit 1
    fi
else
    echo -e "${GREEN}UFW 已安装，跳过安装步骤。${NC}"
    log "UFW 已安装，跳过安装步骤"
fi

echo -e "${YELLOW}设置默认防火墙策略...${NC}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
echo -e "${GREEN}默认策略已设置：拒绝入站，允许出站${NC}"

if sudo ufw allow ssh; then
    echo -e "${GREEN}成功添加SSH规则！${NC}"
else
    echo -e "${RED}添加SSH规则失败！${NC}"
    exit 1
fi

if sudo ufw --force enable; then
    echo -e "${GREEN}UFW 防火墙已启用！${NC}"
else
    echo -e "${RED}启用 UFW 防火墙失败！${NC}"
    exit 1
fi

mkdir -p ~/tools

cat << 'EOF' > ~/tools/ufw_port.sh

if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以root权限运行 (sudo)" 
   exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

open_port() {
    read -p "请输入要开放的端口号: " port
    read -p "请输入该端口的备注: " comment
    echo "选择协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. 所有协议（TCP + UDP）"
    read -p "请选择协议 (1-3): " protocol_choice

    case $protocol_choice in
        1)
            sudo ufw allow "$port"/tcp comment "$comment"
            echo -e "${GREEN}已开放TCP端口 $port，备注: $comment${NC}"
            ;;
        2)
            sudo ufw allow "$port"/udp comment "$comment"
            echo -e "${GREEN}已开放UDP端口 $port，备注: $comment${NC}"
            ;;
        3)
            sudo ufw allow "$port"/tcp comment "$comment"
            sudo ufw allow "$port"/udp comment "$comment"
            echo -e "${GREEN}已开放端口 $port 的所有协议 (TCP 和 UDP)，备注: $comment${NC}"
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            return
            ;;
    esac
}

disable_port() {
    read -p "请输入要禁用的端口号: " port
    read -p "选择协议 (1.TCP 2.UDP 3.所有协议): " protocol_choice

    case $protocol_choice in
        1)
            sudo ufw delete allow "$port"/tcp
            echo -e "${GREEN}已禁用TCP端口 $port${NC}"
            ;;
        2)
            sudo ufw delete allow "$port"/udp
            echo -e "${GREEN}已禁用UDP端口 $port${NC}"
            ;;
        3)
            sudo ufw delete allow "$port"/tcp
            sudo ufw delete allow "$port"/udp
            echo -e "${GREEN}已禁用端口 $port 的所有协议${NC}"
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            return
            ;;
    esac
}
save_rules() {
    read -p "请输入保存文件的路径 (默认: ./ufw_rules.backup): " file_path
    file_path=${file_path:-./ufw_rules.backup}
    ufw status > "$file_path"
    echo -e "${GREEN}规则已保存到 $file_path${NC}"
}

load_rules() {
    read -p "请输入规则文件的路径 (默认: ./ufw_rules.backup): " file_path
    file_path=${file_path:-./ufw_rules.backup}
    if [[ -f "$file_path" ]]; then
        while read -r rule; do
            ufw "$rule"
        done < "$file_path"
        echo -e "${GREEN}规则已从 $file_path 加载${NC}"
    else
        echo -e "${RED}文件不存在：$file_path${NC}"
    fi
}

main_menu() {
    while true; do  
        echo -e "${YELLOW}===== UFW端口管理工具 =====${NC}"
        echo "1. 开放端口"
        echo "2. 查看已开放端口"
        echo "3. 禁用端口"
        echo "4. 保存当前规则"
        echo "5. 加载规则文件"
        echo "0. 退出"
        read -p "请选择操作 (0-5): " choice

        case $choice in
            1)
                open_port
                ;;
            2)
                echo -e "${GREEN}已开放端口列表:${NC}"
                sudo ufw status numbered
                ;;
            3)
                disable_port
                ;;
            4)
                save_rules
                ;;
            5)
                load_rules
                ;;
            0)
                echo -e "${GREEN}感谢使用UFW端口管理工具，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                ;;
        esac
        read -p "按回车键继续..." pause_input
    done
}

main_menu
EOF

chmod +x ~/tools/ufw_port.sh

if ! grep -q "alias n='sudo ~/tools/ufw_port.sh'" ~/.bashrc; then
    echo "alias n='sudo ~/tools/ufw_port.sh'" >> ~/.bashrc
    echo -e "${GREEN}快捷命令 'n' 已成功添加到 .bashrc${NC}"
fi

echo -e "${YELLOW}重新加载 .bashrc 配置以使快捷命令生效...${NC}"
source ~/.bashrc
hash -r

echo -e "${GREEN}UFW端口管理工具安装完成！${NC}"
echo -e "您可以使用快捷命令 'n' 来启动UFW端口管理工具。"
echo -e "如果快捷命令 'n' 无法立即使用，请重新登录您的会话。"
sudo ~/tools/ufw_port.sh  # 自动打开菜单页面
    ;;
       
        3)
echo "执行选项 3：自动申请密钥并配置密钥登录..."
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户运行此脚本。"
    read -n 1 -s -r -p "按任意键返回菜单..."
    continue
fi

KEY_DIR="$HOME/.ssh"
PRIVATE_KEY="$KEY_DIR/id_rsa"
PUBLIC_KEY="$KEY_DIR/id_rsa.pub"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.bak"
CLOUD_INIT_CONFIG="/etc/ssh/sshd_config.d/50-cloud-init.conf"
PAM_SSHD_CONFIG="/etc/pam.d/sshd"

echo "正在生成密钥对..."
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
ssh-keygen -t rsa -b 4096 -f "$PRIVATE_KEY" -N "" -q
if [ $? -ne 0 ]; then
    echo "密钥生成失败，请检查系统配置。"
    read -n 1 -s -r -p "按任意键返回菜单..."
    continue
fi
echo "密钥生成成功！"
echo "密钥文件路径："
echo "私钥: $PRIVATE_KEY"
echo "公钥: $PUBLIC_KEY"

echo "生成公钥的 ASCII 图形化表示..."
ssh-keygen -lv -f "$PUBLIC_KEY"

if [ ! -f "$BACKUP_CONFIG" ]; then
    cp "$SSHD_CONFIG" "$BACKUP_CONFIG"
    echo "sshd 配置文件已备份到 $BACKUP_CONFIG。"
else
    echo "sshd 配置文件已存在备份，跳过备份步骤。"
fi

echo "正在配置公钥登录..."
AUTHORIZED_KEYS="$KEY_DIR/authorized_keys"
cat "$PUBLIC_KEY" >> "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"
chown -R "$(whoami):$(whoami)" "$KEY_DIR"
echo "公钥已添加到 $AUTHORIZED_KEYS。"

echo "修改 SSH 配置以禁用密码登录..."
if ! grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
    echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
fi
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#PasswordAuthentication no/PasswordAuthentication no/' "$SSHD_CONFIG"
if ! grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG"; then
    echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
fi
if ! grep -q "^ChallengeResponseAuthentication no" "$SSHD_CONFIG"; then
    echo "ChallengeResponseAuthentication no" >> "$SSHD_CONFIG"
fi
if grep -q "^UsePAM yes" "$SSHD_CONFIG"; then
    sed -i 's/^UsePAM yes/UsePAM no/' "$SSHD_CONFIG"
fi

if [ -f "$CLOUD_INIT_CONFIG" ]; then
    echo "检测到 $CLOUD_INIT_CONFIG，清空文件并添加 PasswordAuthentication no..."
    
    > "$CLOUD_INIT_CONFIG"
    
    echo "PasswordAuthentication no" >> "$CLOUD_INIT_CONFIG"

    if grep -q "^PasswordAuthentication no" "$CLOUD_INIT_CONFIG"; then
        echo "成功修改 $CLOUD_INIT_CONFIG 中的 PasswordAuthentication 为 no。"
    else
        echo "修改 $CLOUD_INIT_CONFIG 失败，请手动检查文件。"
    fi
fi

if [ -f "$PAM_SSHD_CONFIG" ]; then
    echo "注释掉 PAM 配置中的 @include common-auth..."
    sed -i 's/^@include common-auth/#@include common-auth/' "$PAM_SSHD_CONFIG"
fi

echo -e "${DARK_RED}重要提示：${NC}"
echo -e "${DARK_RED}‼️  切记要先保存好私钥！！！。${NC}"
echo -e "${DARK_RED}‼️  退出菜单输入以下重启命令:${NC}"

echo -e "${DARK_RED}‼️  systemctl restart sshd${NC}"

echo -e "${DARK_RED}‼️  然后重启SSH禁用密码才会被加载生效、然后用私钥登录${NC}"

echo -e "${BRIGHT_GREEN}公钥路径: $PUBLIC_KEY${NC}"
echo -e "${BRIGHT_GREEN}私钥路径: $PRIVATE_KEY${NC}"

echo ""
read -n 1 -s -r -p "按任意键返回菜单..."
echo ""
        ;;
        4)
            execute_script "https://gist.githubusercontent.com/momo97620/685e1ead90ed0ad379c6a75e27409704/raw/aaeabe347f3612e9c308b898e64bcfd12276a067/duank" "修改登录端口号完成。"
            ;;
        5)
            execute_script "https://github.com/233boy/sing-box/raw/main/install.sh" "一键搭建节点完成。"
            ;;
        6)
            execute_script "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" "一键WARP完成。"
            ;;
        7)
            execute_script "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcp.sh" "BBR加速完成。"
            ;;
        8)
while true; do
    clear  # 清除屏幕
check_ldnmp() {
    if command -v php &> /dev/null; then
        php_version="PHP: $(php -v | head -n 1 | awk '{print $2}')"
    else
        php_version="PHP: 未安装"
    fi

    if command -v mysql &> /dev/null; then
        mysql_version="MySQL: $(mysql --version | awk '{print $5}')"
    else
        mysql_version="MySQL: 未安装"
    fi

    if command -v nginx &> /dev/null; then
        nginx_version="Nginx: $(nginx -v 2>&1 | awk -F/ '{print $2}')"
    else
        nginx_version="Nginx: 未安装"
    fi
    if command -v docker &> /dev/null; then
        docker_version="Docker: $(docker --version | awk '{print $3}' | sed 's/,//')"
    else
        docker_version="Docker: 未安装"
    fi
              echo -e "${BLUE}\n===== LDNMP 环境检测 =====${NC}"
    # 输出结果为一排
    echo -e "${BOLD_GREEN} ${docker_version} | ${mysql_version} | ${php_version} | ${nginx_version}${NC}"
    
    echo -e "${DEEPRED}-----------------------------${NC}"
}
check_ldnmp 
    echo -e "${GREEN}1.${NC} ${LIGHTBLUE}docker安装${NC}"
    echo -e "----------------------------"
    echo -e "${BLUE}2.${NC} ${LIGHTCYAN}容器管理${NC}"
    echo -e "----------------------------"
    echo -e "${DEEPRED}3.${NC} ${RED}镜像管理${NC}"
    echo -e "----------------------------"
    echo -e "${YELLOW}4.${NC} ${PINK}NextChatGPT${NC}"
    echo -e "----------------------------"
    echo -e "${LIGHTBLUE}5.${NC} ${GREEN}简单图床2.0${NC}"
    echo -e "----------------------------"
    echo -e "${LIGHTBLUE}6.${NC} ${GREEN}自动备份${NC}" 
    echo -e "----------------------------"
    echo -e "${LIGHTBLUE}7.${NC} ${NC}哪吒监控${NC}"
    echo -e "----------------------------"
    echo -e "${DEEPRED}0.${NC} ${RED}返回主菜单${NC}" 
    echo -e "============================"
echo -e "${LIGHTCYAN}⚠️ 所有项目安装前需要先安装 Docker！否则提示安装失败。${NC}"

    read -p "请输入你的选择 [1-7, 0]: " sys_choice

    case $sys_choice in
        1)
            install_docker
            ;;
        4)
            clear  # 清除屏幕
GREEN='\033[0;32m'
RED='\033[0;31m'
BRIGHT_GREEN='\033[1;32m'
DEEPRED='\033[1;31m'  # 深红色
NC='\033[0m'          # 无颜色
  

if ! grep -q "export LANG=en_US.UTF-8" ~/.bashrc; then
    echo "export LANG=en_US.UTF-8" >> ~/.bashrc
fi

if ! grep -q "export LC_ALL=en_US.UTF-8" ~/.bashrc; then
    echo "export LC_ALL=en_US.UTF-8" >> ~/.bashrc
fi

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

setup_nextchat() {
    local work="/docker/nextchat"
    mkdir -p "$work" && cd "$work" || { echo "无法进入工作目录"; exit 1; }

    cat <<EOL > docker-compose.yml
version: '3'
services:
  chatgpt-next-web:
    container_name: nextchat
    image: yidadaa/chatgpt-next-web:latest
    restart: always
    ports:
      - "8842:3000"
    environment:
      - OPENAI_API_KEY=sk-xxx #你的api key
      - CODE=emomomo  #密码
      - BASE_URL=https://xx.xx.io #第三方代理地址
      - DEFAULT_MODEL=gpt-4o-mini  #默认模型
      - ENABLE_BALANCE_QUERY=1  #启用余额查询
EOL

    if docker-compose up -d; then
        echo -e "${GREEN}✅ Docker 容器启动成功！${NC}"
    else
        echo -e "${RED}❌ Docker 容器启动失败！请检查是否安装docker-compose。${NC}"
        exit 1
    fi

     echo -e "${BRIGHT_GREEN}✅ 已成功安装！${NC}"
                
    echo -e "${DEEPRED}1.${NC} ⚠️ ${DEEPRED}请手动放行8842端口！！${NC}"
    
    echo -e "${DEEPRED}2.${NC} ⚠️ ${DEEPRED}后台登录方式：本机IP+8842！！${NC}"
    
    echo -e "${DEEPRED}3.${NC} ⚠️ ${DEEPRED}如遇到需要管理员密码:emomomo！！${NC}"
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

setup_nextchat
        ;;
        
        2)
            container_management
                ;;
        7)
            curl -L https://raw.githubusercontent.com/nezhahq/scripts/refs/heads/main/install.sh -o nezha.sh && chmod +x nezha.sh && ./nezha.sh
                ;;   

        5)
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，请先安装 Docker。"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose 未安装，请先安装 Docker Compose。"
    exit 1
fi

mkdir -p /root/data/docker_data/easyimage
if [ $? -ne 0 ]; then
    echo "创建目录失败，请检查权限或磁盘空间。"
    exit 1
fi

cd /root/data/docker_data/easyimage || { echo "无法进入目录，请检查路径。"; exit 1; }

cat > docker-compose.yml <<EOF
version: '3.3'
services:
  easyimage:
    image: ddsderek/easyimage:latest
    container_name: easyimage
    ports:
      - '8080:80'
    environment:
      - TZ=Asia/Shanghai
      - PUID=1000
      - PGID=1000
    volumes:
      - '/root/data/docker_data/easyimage/config:/app/web/config'
      - '/root/data/docker_data/easyimage/i:/app/web/i'
    restart: unless-stopped
EOF
if [ $? -ne 0 ]; then
    echo "创建 docker-compose.yml 文件失败。"
    exit 1
fi

docker-compose up -d
if [ $? -ne 0 ]; then
    echo "启动容器失败，请检查 Docker 和 Compose 的状态。"
    exit 1
fi

echo "已安装成功，请手动放行8080端口，使用IP+8080浏览器登录。"

read -n 1 -s -r -p "按任意键返回上一页..."

            ;;
            
        3)
           image_management #镜像管理
            ;;  
            
        6)
            backup_menu
            ;;
            
        0)
            echo "返回主菜单..."
            break
            ;;
        *)
            clear  # 清除屏幕
            echo "无效选择，请重新输入！"
            read -p "按任意键继续..."
            ;;
    esac
done
            ;;    
        9)
            execute_script "https://raw.githubusercontent.com/momo97620/momoya/main/xitong" "系统信息查询完成。"
            ;;
        10)
            set_ip_priority
            ;;
        11)
            update_script
            ;;
        12) 
            set_ssh_keepalive
            ;;
        13) 
 while true; do
    clear
    echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}            DD重装系统            ${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "\n${BLUE}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}\n"  # 美化空行

echo -e "${GREEN}1.${NC} 国外服务器"
echo -e "\n${BLUE}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}\n"  # 美化空行
echo -e "${GREEN}2.${NC} 国内服务器"
echo -e "\n${BLUE}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}\n"  # 美化空行
echo -e "${GREEN}3.${NC} 另一个DD(史上最强)"
echo -e "\n${BLUE}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}\n"  # 美化空行
echo -e "${GREEN}0.${NC} 返回主菜单"
echo -e "\n${BLUE}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}\n"  # 美化空行
echo -e "\n"  # 添加空行
read -p "请输入选项 [1-3，0]: " sub_choice  

    case $sub_choice in
        1)
            curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh $_
            ;;
        2)
            curl -O https://jihulab.com/bin456789/reinstall/-/raw/main/reinstall.sh || wget -O reinstall.sh $_
            ;;
        3)
            curl -O https://raw.githubusercontent.com/momo97620/momoya/refs/heads/main/dd && chmod +x dd && ./dd
            ;;
        0)
            echo "返回主菜单..."
                break
            ;;
        *)
            echo -e "${RED}无效选项!${NC}"
            sleep 2
            continue
            ;;
    esac

    chmod +x reinstall.sh
    while true; do
        clear
        echo -e "${BLUE}----------------------------------------${NC}"
        echo -e "${BLUE}            选择您的系统版本            ${NC}"
        echo -e "${BLUE}----------------------------------------${NC}"
        echo -e "${GREEN}1.${NC} Debian 10"
        echo -e "${GREEN}2.${NC} Debian 11"
        echo -e "${GREEN}3.${NC} Debian 12"
        echo -e "${GREEN}4.${NC} Ubuntu 16.04"
        echo -e "${GREEN}5.${NC} Ubuntu 18.04"
        echo -e "${GREEN}6.${NC} Ubuntu 20.04"
        echo -e "${GREEN}7.${NC} Ubuntu 24.04"
        echo -e "${GREEN}0.${NC} 返回上级菜单"
        echo -e "${BLUE}----------------------------------------${NC}"
        read -p "请输入选项 [1-7，0]: " version_choice

        case $version_choice in
            1)
                bash reinstall.sh "Debian 10"
                ;;
            2)
                bash reinstall.sh "Debian 11"
                ;;
            3)
                bash reinstall.sh "Debian 12"
                ;;
            4)
                bash reinstall.sh "Ubuntu 16.04"
                ;;
            5)
                bash reinstall.sh "Ubuntu 18.04"
                ;;
            6)
                bash reinstall.sh "Ubuntu 20.04"
                ;;
            7)
                bash reinstall.sh "Ubuntu 24.04"
                ;;
            0)
                echo "返回主菜单..."
                break
                ;;
            *)
                echo -e "${RED}无效选项!${NC}"
                sleep 2
                ;;
        esac
    done
done

            ;;  
        14) 
             execute_script "https://raw.githubusercontent.com/ecouus/Feed-Push/refs/heads/main/bot_deploy.sh" "TG关键词订阅部署完成。"
            ;;  
        15)
            RAINBOW_PROMPT::main
            ;;
        16)
            while true; do
            clear
            echo -e "${BLUE}----------------------------------------${NC}"
            echo -e "${BLUE}            测试流媒体子菜单            ${NC}"
            echo -e "${BLUE}----------------------------------------${NC}"
            echo -e "${GREEN}1.${NC} 流媒体测试"
            echo -e "${GREEN}2.${NC} 融合怪测试"
            echo -e "${GREEN}0.${NC} 返回主菜单"
            echo -e "${BLUE}----------------------------------------${NC}"
            read -p "请输入选项 [0-2，0]: " sub_choice

        case $sub_choice in
            1)
                bash <(curl -sL IP.Check.Place)
                ;;
            2)
                curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
                ;;
            0)
                echo "返回主菜单..."
                break
                ;;
            *)
                echo -e "${RED}无效选项!${NC}"
                sleep 2
                ;;
        esac
    done
    ;;
            17)
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本。"
  exit
fi

install_caddy() {
  sudo apt update
  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

  sudo apt update
  sudo apt install -y caddy
}

configure_proxy() {
  read -p "请输入你的反代域名: " domain
  read -p "请输入你要反代的 IP:端口: " proxy_target

  if [[ "$proxy_target" =~ \[.*\] ]]; then
    true
  elif [[ "$proxy_target" =~ : ]]; then
    ip="${proxy_target%:*}"
    port="${proxy_target##*:}"
    proxy_target="[$ip]:$port"
  fi

  if grep -q "$domain" /etc/caddy/Caddyfile; then
    echo "域名 $domain 已存在，跳过添加。"
  else
    sudo bash -c "echo '$domain {' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '    tls mail@mail.com' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '    encode gzip' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '    reverse_proxy $proxy_target {' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '        header_up Host {host}' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '        header_up X-Real-IP {remote}' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '        header_up X-Forwarded-For {remote}' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '    }' >> /etc/caddy/Caddyfile"
    sudo bash -c "echo '}' >> /etc/caddy/Caddyfile"
    echo "已添加域名 $domain 的反向代理配置。"
  fi

  sudo systemctl reload caddy
}

view_configurations() {
  echo "已配置的反向代理:"
  grep -E '^\S+' /etc/caddy/Caddyfile | awk '{print $1}' | sort -u

  echo -e "\n已配置的证书:"
  sudo ls /etc/letsencrypt/live
}

delete_proxy() {
  echo "已配置的反向代理:"
  domains=( $(grep -E '^\S+' /etc/caddy/Caddyfile | awk '{print $1}' | sort -u) )
  
  if [ ${#domains[@]} -eq 0 ]; then
    echo "没有可删除的反向代理配置。"
    return
  fi

  select domain in "${domains[@]}"; do
    if [ -n "$domain" ]; then
      echo "正在删除域名 $domain 的反向代理配置..."
      sudo sed -i "/^$domain {/,/^}/d" /etc/caddy/Caddyfile
      echo "已删除域名 $domain 的反向代理配置。"
      break
    else
      echo "无效选择，请重新选择。"
    fi
  done

  sudo systemctl reload caddy
}

while true; do
  echo "请选择一个功能:"
  echo "1. 配置反向代理"
  echo "2. 查看已配置的 IP 和证书"
  echo "3. 删除反向代理配置"
  echo "0. 退出"
  
  read -p "请输入选项 (1/2/3/0): " option

  case $option in
    1)
      configure_proxy
      ;;
    2)
      view_configurations
      ;;
    3)
      delete_proxy
      ;;
    0)
      echo "退出程序。"
      exit 0
      ;;
    *)
      echo "无效选项，请重新选择。"
      ;;
  esac

  echo -e "\n按任意键返回菜单..."
  read -n 1 -s
  echo
done
            ;;
            0)
              echo -e "${GREEN}退出程序...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选择，请重新输入！${NC}"
            ;;
    esac
}


main() {
    
    if [[ "$1" == "install" ]]; then
        install_script
        exit 0
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        install_script
    else
        echo -e "${GREEN}脚本已安装到：$INSTALL_DIR${NC}" &>/dev/null
    fi
    
    
    
    initialize_script
    while true; do
    set_shanghai_time
        show_main_menu
    done
}

main "$@"
