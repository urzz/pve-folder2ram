#!/bin/bash

echo "install pve-folder2ram? (y\n)"
read x
if [ $x == 'y' ];then
   apt -y install  wget
   wget -O /sbin/folder2ram https://raw.githubusercontent.com/bobafetthotmail/folder2ram/master/debian_package/sbin/folder2ram
   chmod +x /sbin/folder2ram
   mkdir /etc/folder2ram
   cat << EOF > /etc/folder2ram/folder2ram.conf
tmpfs           /var/log
tmpfs           /var/tmp
tmpfs           /var/cache
tmpfs           /tmp
EOF
   folder2ram -enablesystemd
   folder2ram -mountall
   
   cat << EOF > /usr/bin/truncLog
#!/bin/bash

isFile(){
        L=\`cat $1|wc -l\`
        n=$(($L - 150))
        if [ $n -gt 0 ];then
                sed -i "1,${n}d" $1
        fi
}

isDir(){
        echo $1
        for i in \`ls $1\`
        do
                if [ -f $1/$i ];then
                        isFile $1/$i
                else
                        isDir $1/$i
                fi
        done
}

isDir '/var/log'
EOF
    chmod +x /usr/bin/truncLog
    echo "" >> /etc/crontab
    echo "@reboot */10 *	*	*	*	root	/usr/bin/truncLog" >> /etc/crontab
    systemctl restart cron
    echo "done."
else
    exit
fi