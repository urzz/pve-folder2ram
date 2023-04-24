#!/bin/bash

# 配置文件路径
CONF_FILE="/etc/folder2ram/folder2ram.conf"
# 需要保留的日志行数
LOG_LINES=1000

# 安装依赖
echo "Installing dependencies ..."
apt -y install wget

# 下载并安装 folder2ram
echo "Installing folder2ram ..."
wget -O /sbin/folder2ram https://ghproxy.com/https://raw.githubusercontent.com/bobafetthotmail/folder2ram/master/debian_package/sbin/folder2ram
chmod +x /sbin/folder2ram

# 创建配置文件目录和配置文件, type和path必须要空两个\t, 否则 folder2ram 无法识别
echo "Creating configuration files ..."
mkdir -p $(dirname "$CONF_FILE")
echo -e "tmpfs\t\t/var/log" >"$CONF_FILE"
echo -e "tmpfs\t\t/var/tmp" >>"$CONF_FILE"
echo -e "tmpfs\t\t/var/cache" >>"$CONF_FILE"
echo -e "tmpfs\t\t/tmp" >>"$CONF_FILE"

# 启用 folder2ram
echo "Enabling folder2ram ..."
folder2ram -enablesystemd
folder2ram -umountall
folder2ram -mountall

# 创建日志文件清理脚本
echo "Creating log truncation script ..."
cat <<EOF >/sbin/trunc_ram_log
#!/bin/bash

# Truncate all files in a directory (recursively) to the last N lines
# Usage: truncLog <directory> <number_of_lines>

truncLog() {
    for file in "\$1"/*; do
        if [ -d "\$file" ]; then
            echo "Processing directory: \$file"
            truncLog "\$file" "\$2"
        elif [ -f "\$file" ]; then
            echo "Truncating file: \$file"
            tail -n "\$2" "\$file" >"\$file.tmp"
            mv "\$file.tmp" "\$file"
        fi
    done
}

# Clean up all non-log files in a directory (recursively)
# Usage: cleanDir <directory>

cleanDir() {
    for file in "\$1"/*; do
        if [ -d "\$file" ]; then
            echo "Processing directory: \$file"
            cleanDir "\$file"
        elif [ -f "\$file" ]; then
            case "\$file" in
            *.log | *.log.* | *.info | *.warn | *.journal)
                # keep log files
                ;;
            *)
                echo "Removing file: \$file"
                rm "\$file"
                ;;
            esac
        fi
    done
}

# Main script
if [ "\$#" -ne 2 ]; then
    echo "Usage: \$0 <directory> <number_of_lines>"
    exit 1
fi

dir="\$1"
lines="\$2"

if [ ! -d "\$dir" ]; then
    echo "\$dir is not a directory"
    exit 1
fi

echo "Truncating log files in directory: \$dir to \$lines lines"
truncLog "\$dir" "\$lines"
echo "Cleaning up non-log files in directory: \$dir"
cleanDir "\$dir"
EOF
chmod +x /sbin/trunc_ram_log

# 添加清理脚本到定时任务
echo "Adding log truncation script to cron ..."
(
        crontab -l
        echo "*/30 * * * * root /sbin/trunc_ram_log /var/log 1000"
) | crontab -
