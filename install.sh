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
# Usage: truncLog <directory> <number_of_lines> [<ignore_dirs>]

processed_files=\$(mktemp)
trap 'rm -f "\$processed_files"' EXIT

truncLog() {
    local dir="\$1"
    local lines="\$2"
    local ignore_dirs="\$3"
    for file in "\$dir"/*; do
        if [ -d "\$file" ]; then
            local skip=false
            for ignore_dir in \$ignore_dirs; do
                if [[ "\$file" == "\$ignore_dir"/* ]]; then
                    echo "Skipping directory: \$file"
                    skip=true
                    break
                fi
            done
            if ! "\$skip"; then
                echo "Processing directory: \$file"
                truncLog "\$file" "\$lines" "\$ignore_dirs"
            fi
        elif [ -f "\$file" ]; then
            local log_files=".journal"
            if grep -q "\$file" "\$processed_files"; then
                # Skip files that have already been truncated
                continue
            fi
            local file_name=\$(basename "\$file")
            local file_ext="\${file_name##*.}"
            if [[ "\$log_files" == *".\$file_ext"* ]]; then
                # Skip file
                echo "Skip truncate file: \$file"
                continue
            fi
            echo "Truncating file: \$file"
            tail -n "\$2" "\$file" >"\$file.tmp"
            mv "\$file.tmp" "\$file"
            echo "\$file" >>"\$processed_files"
        fi
    done
}

# Clean up all non-log files in a directory (recursively)
# Usage: cleanDir <directory> [<ignore_dirs>]

cleanDir() {
    local dir="\$1"
    local ignore_dirs="\$2"

    for file in "\$dir"/*; do
        if [ -d "\$file" ]; then
            local skip=false
            for ignore_dir in \$ignore_dirs; do
                if [[ "\$file" == "\$ignore_dir"/* ]]; then
                    echo "Skipping directory: \$file"
                    skip=true
                    break
                fi
            done
            if ! "\$skip"; then
                echo "Processing directory: \$file"
                cleanDir "\$file" "\$ignore_dirs"
            fi
        elif [ -f "\$file" ]; then
            local log_files=".log .info .warn .journal"
            if [[ "\$log_files" == *"\$file"* ]]; then
                # Keep log files
                continue
            fi
            echo "Removing file: \$file"
            rm "\$file"
        fi
    done
}

# Main script
if [ "\$#" -lt 2 ]; then
    echo "Usage: \$0 <directory> <number_of_lines> [<ignore_dirs>]"
    exit 1
fi

dir="\$1"
lines="\$2"
ignore_dirs="\${3:-}"

if [ ! -d "\$dir" ]; then
    echo "\$dir is not a directory"
    exit 1
fi

echo "Truncating log files in directory: \$dir to \$lines lines"
truncLog "\$dir" "\$lines" "\$ignore_dirs"
echo "Cleaning up non-log files in directory: \$dir"
cleanDir "\$dir" "\$ignore_dirs"
EOF
chmod +x /sbin/trunc_ram_log

# 添加清理脚本到定时任务
echo "Adding log truncation script to cron ..."
(
    crontab -l
    echo "*/30 * * * * /sbin/trunc_ram_log /var/log 1000 \"/var/log/pve /var/log/ceph /var/log/journal\" > /tmp/pve-folder2ram-trunc.log"
) | crontab -
