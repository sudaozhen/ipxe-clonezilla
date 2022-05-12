#!/bin/bash
###
 # @File         : 
 # @version      : 
 # @Author       : Su Daozhen
 # @Date         : 2022-02-19 17:56:58
 # @LastEditors  : Su Daozhen
 # @LastEditTime : 2022-03-02 22:43:45
 # @Encoding     : UTF-8
 # @Description  : 
 # @Attention    : 
 # ********************COPYRIGHT 2022 Su Daozhen********************
### 
version="v0.1 beta";
cur_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)";
app_dir=$cur_dir/app
#################### VARIABLES #################### 
MAIN_DIR="/data"

LOG_DIR="${MAIN_DIR}/log"
LOG_FILE_NAME="${LOG_DIR}/run_pxe.log"
#文件大小这里以行数来计算
FSIZE=2000000

#HTML_DIR="/usr/share/nginx/html"    #HTML_DIR is nginx / dir,and copy centos dvd to this dir  
NAME_SERVER="10.1.0.5"              #NAME_SERVER is for  dhcpd.conf domain-name-servers   
SUBNET="10.1.0.0"                   #SUBNET is for  dhcpd.conf subnet 
NETMASK="255.255.255.0"             #NETMASK is for dhcpd.conf  netmask  
RANG_START="10.1.0.10"              #RANG_START is for dhcpd.conf  range start  
RANG_END="10.1.0.225"               #RANG_END is  for dhcpd.conf  rang end 
NEXT_SERVER="10.1.0.5"              #NEXT_SERVER is for dhcpd.conf  next_server  

PXEBOOT_DIR="${MAIN_DIR}/pxeboot"   #pxe boot dir 
CLONEZILLA_IMAG_DIR="${MAIN_DIR}/imag"          #clonezilla backup path
WWWROOT_DIR="${MAIN_DIR}/wwwroot"
PXEFILES_DIR="${WWWROOT_DIR}/pxefiles"
PXELINUX_DIR="${PXEFILES_DIR}/pxelinux.cfg"     #pxelinux.cfg dir  
ISO_DIR="${PXEFILES_DIR}/iso"
ISO_MNT_DIR="${ISO_DIR}/mnt/iso"                  #ISO_MNT is CentOS DVD mount dir 
CLONEZILLA_MNT_DIR="${ISO_DIR}/clonezilla"
CLONEZILLA_USER="clonezilla"
CLONEZILLA_PASSWD="111111"

PXEFILES_URL="http://$NAME_SERVER/pxefiles"
ISO_URL="${PXEFILES_URL}/iso"
CLONEZILLA_MNT_URL="${ISO_URL}/clonezilla"
ISO_MNT_URL="${ISO_URL}/mnt"
#################### FUCTIONS #####################
_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

_magenta() {
    printf '\033[1;31;35m%b\033[0m' "$1"
}

_info() {
    _green "[Info] "
    printf -- "%s" "$1"
    printf "\n"
    _log "[Info] $1"
}

_warn() {
    _yellow "[Warning] "
    printf -- "%s" "$1"
    printf "\n"
    _log "[Warning] $1"
}

_error() {
    _red "[Error] "
    printf -- "%s" "$1"
    printf "\n"
    _log "[Error] $1"
    echo "For more details, please check the log file: ${LOG_FILE_NAME}" 
    exit 1
}


_log() {
        #judge the params,it must 2 params;
    if [ 1 -gt $# ]
    then
        echo  "WARN parameter not correct in log function"
        return;
    fi
    #如果日志的根目录不存在，则应该先创建
    if [ ! -d $LOG_DIR ];then
        mkdir -p $LOG_DIR
    fi
    #判断日志文件是否存在，不存在则创建
    if [ ! -e "$LOG_FILE_NAME" ];then
        touch $LOG_FILE_NAME
    fi
    #日志时间
    local curtime
    curtime=$(date +"%F %T")
    #判断日志的大小，然后如果对于指定的行数，则应该备份旧的日志文件，然后创建新的日志文件
    local cursize
    if [ ! -e "$LOG_FILE_NAME" ];then
        echo "There is no log file!Not record log to file!"
        return
    fi
    # 计算现有的日志文件的行数
    cursize=$(cat $LOG_FILE_NAME | wc -c)
    if [ $FSIZE -lt "$cursize" ];then
        echo "backup old log file"
        # 备份文件名为：日期.log
        mv $LOG_FILE_NAME "$curtime"".log"
        # 创建新的日志文件
        touch $LOG_FILE_NAME
    fi  
    # 打印控制台日志和记录日志到文件
    echo "$curtime $*">> $LOG_FILE_NAME
}

function _dnsmasq() {
    local src_file_name
    case $1 in
        install) 
            src_file_name="$(ls "$app_dir" | grep dnsmasq)" || _error "dnsmasq: No dnsmasq packages!"; 
            mkdir -p /usr/local/src;
            cp -f "$app_dir/$src_file_name" /usr/local/src;
            cd /usr/local/src || _error "dnsmasq: Unknow dir /usr/local/src";
            tar -xf "$src_file_name" && rm -f "$src_file_name"
            (cd /usr/local/src/dnsmasq* &&  ( make -j8 )) || _error "dnsmasq: Unknow dir /usr/local/src/dnsmasq*";
            #cp -p /usr/local/src/dnsmasq*/src/dnsmasq /usr/local/bin
            /usr/local/src/dnsmasq*/src/dnsmasq -v | grep version;
        ;;
        uninstall) 
            #rm -f /usr/local/bin/dnsmasq;
            (rm -rf /usr/local/src/dnsmasq* && _info "dnsmasq: Uninstall dnsmasq OK.") || _warn "dnsmasq: Uninstall dnsmasq failed.";
        ;;
        start) 
            (/usr/local/src/dnsmasq*/src/dnsmasq -C $PXEBOOT_DIR/dnsmasq.conf \
            && _info "dnsmasq: Start dnsmasq OK." ) || _warn "dnsmasq: Start dnsmasq failed.";
            #sleep 1;
            #echo _services_status dnsmasq;
            if _services_status dnsmasq; then
                _info "dnsmasq: Dnsmasq active.";
            else
                _warn "dnsmasq: Dnsmasq inactive.";
            fi
            ;;
        stop) 
            (kill -9 "$(pidof dnsmasq)">/dev/null && _info "dnsmasq: Stop dnsmasq OK") || _warn "dnsmasq: Stop dnsmasq failed.";
            if _services_status dnsmasq; then
                _warn "dnsmasq: Dnsmasq active.";
            else
                _info "dnsmasq: Dnsmasq inactive.";
            fi
            ;;
        restart)
            _dnsmasq stop; _dnsmasq start; ;;
        conf) 
            mkdir -p $PXEBOOT_DIR
            echo -e \
"#BISO UEFI均能启动
#biso引导undionly.kpxe->pxelinux.0
#UEFI引导UEFI/ipxe.efi
# Don't function as a DNS server:
port=0

# enable dhcp
dhcp-range=$RANG_START,$RANG_END,$NETMASK,12h
dhcp-option=option:router,$NAME_SERVER
dhcp-option=option:dns-server,114.114.114.114,119.29.29.29

# Log lots of extra information about DHCP transactions.
log-dhcp
dhcp-vendorclass=bios,PXEClient:Arch:00000

dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:NEC/PC98,option:client-arch,1
dhcp-match=set:EFI_Itanium,option:client-arch,2
dhcp-match=set:DEC_Alpha,option:client-arch,3
dhcp-match=set:Arc_x86,option:client-arch,4
dhcp-match=set:Intel_Lean_Client,option:client-arch,5
dhcp-match=set:EFI_IA32,option:client-arch,6
dhcp-match=set:EFI_BC,option:client-arch,7
dhcp-match=set:EFI_Xscale,option:client-arch,8
dhcp-match=set:EFI_x86-64,option:client-arch,9
#dhcp-match=set:EFI_ARM32,option:client-arch,?
#dhcp-match=set:EFI_ARM64,option:client-arch,?

dhcp-match=set:ipxe,175
dhcp-boot=tag:!ipxe,tag:bios,Legacy/undionly.kpxe

dhcp-boot=tag:!ipxe,tag:EFI_BC,UEFI/ipxe.efi
dhcp-boot=tag:!ipxe,tag:EFI_Xscale,UEFI/ipxe.efi
dhcp-boot=tag:!ipxe,tag:EFI_x86-64,UEFI/ipxe.efi

#dhcp-boot=tag:!ipxe,tag:EFI_x86-64,UEFI/ipxe.efi
#dhcp-boot=tag:!ipxe,tag:!bios,UEFI/ipxe.efi
#dhcp-boot=tag:ipxe,boot.ipxe
#dhcp-boot=tag:ipxe,http://boot.netboot.xyz
enable-tftp
tftp-root=$PXEBOOT_DIR">$PXEBOOT_DIR/dnsmasq.conf
            _info "dnsmasq: configure file set OK."
        ;;
        # interface)
        #     ifconfig eno16777736:10 $NAME_SERVER netmask $NETMASK;
        #     _info "dnsmasq: interface set OK."
        # ;;
    esac
  
}

function _nginx() {
    local src_file_name;
    case $1 in
        install)
            src_file_name="$(ls "$app_dir" | grep nginx)" || _error "No nginx packages!"; 
            mkdir -p /usr/local/src;
            cp -f "$app_dir/$src_file_name" /usr/local/src;
            cd /usr/local/src || _error "Unknow dir /usr/local/src";
            tar -xzf "$src_file_name" && rm -f "$src_file_name"
            cd /usr/local/src/nginx* || _error "Unknow dir /usr/local/src/dnsmasq*";
            ./configure --prefix=/usr/local/nginx --without-http_rewrite_module || _error "nginx: configure error."
            make -j8 && make install || _error "nginx: make error."
            #cp -p /usr/local/src/dnsmasq*/src/dnsmasq /usr/local/bin
            /usr/local/nginx/sbin/nginx -v;
            ;;
        uninstall)
            rm -rf /usr/local/nginx/ && _info "nginx: remove OK." || _warn "nginx: remove failed."; ;;
        start) 
            (/usr/local/nginx/sbin/nginx && _info "nginx: Start nginx OK." ) || _warn "nginx: Start nginx failed."; 
            if _services_status nginx; then
                _info "nginx: Status active.";
            else
                _warn "nginx: Status inactive.";
            fi;;
        stop) 
            (kill -9 $(pidof nginx)>/dev/null && _info "nginx: Stop nginx OK.") || _warn "nginx: Stop nginx failed.";
            if _services_status nginx; then
                _warn "nginx: Status active.";
            else
                _info "nginx: Status inactive.";
            fi
            ;;
        restart) _nginx stop; _nginx start; ;;
        conf)
            mkdir -p $PXEFILES_DIR;
            echo -e \
"worker_processes  4;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    autoindex       on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  localhost;
        location / {
            root   $WWWROOT_DIR;
            index  index.html index.htm;
        }
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}">/usr/local/nginx/conf/nginx.conf; ;;
    esac
}
function _ipxe() {
    local menu_list;
    case $1 in
        Legacy_boot)
            mkdir -p $PXEBOOT_DIR/Legacy;
            cp -p $app_dir/undionly.kpxe $PXEBOOT_DIR/Legacy/;
            echo -e \
"#!ipxe
#Legacy
set 210:string $PXEFILES_URL/
set 209:string pxelinux.cfg/default
chain \${210:string}pxelinux.0">$PXEBOOT_DIR/Legacy/menu.ipxe
            mkdir -p $PXEFILES_DIR;
            cp -p $app_dir/memdisk $app_dir/vesamenu.c32 $app_dir/pxelinux.0 $PXEFILES_DIR/;
            _info "ipxe: ipxe Legacy boot file set OK."
            ;;
        UEFI_boot)
            mkdir -p $PXEBOOT_DIR/UEFI;
            cp -p $app_dir/ipxe.efi $PXEBOOT_DIR/UEFI/;
            _info "ipxe: ipxe UEFI boot file set OK."
            ;;
        Legacy_conf) pass; ;;
        UEFI_conf) pass ;  ;;
        clonezilla_conf)
            mkdir -p $CLONEZILLA_IMAG_DIR $CLONEZILLA_MNT_DIR;
            useradd $CLONEZILLA_USER;
            # echo "$CLONEZILLA_PASSWD" |passwd --stdin $CLONEZILLA_USER;
            passwd $CLONEZILLA_USER << EOF
$CLONEZILLA_PASSWD
$CLONEZILLA_PASSWD
EOF
            setfacl -m u:$CLONEZILLA_USER:rwx $CLONEZILLA_IMAG_DIR;
            ls $app_dir | grep clonezilla || _error "clonezilla: No clonezilla iso file.";
            mount | grep $CLONEZILLA_MNT_DIR || mount -o loop $app_dir/clonezilla*.iso $CLONEZILLA_MNT_DIR;
        ;;
        Legacy_menu)
            mkdir -p $PXELINUX_DIR;
            echo -e \
"default vesamenu.c32
timeout 30
menu title Welcome to Legacy iPXE menu
#menu background splash.jpg
menu color border 0 #ffffffff #00000000
menu color sel 7 #ffffffff #ff000000
menu color title 0 #ffffffff #00000000
menu color tabmsg 0 #ffffffff #00000000
menu color unsel 0 #ffffffff #00000000
menu color hotsel 0 #ff000000 #ffffffff
menu color hotkey 7 #ffffffff #ff000000
menu color scrollbar 0 #ffffffff #00000000

label local_boot
    menu default
    menu label Boot from local drive
    localboot 0xffff

label clonezilla_ISO
    menu label boot clonezilla
    kernel memdisk
    append initrd=/iso/clonezilla.iso ksdevice=bootif raw iso

label clonezilla_backup_from_sda
    menu label clonezilla backup disk from sda
    kernel $CLONEZILLA_MNT_URL/live/vmlinuz 
    append initrd=$CLONEZILLA_MNT_URL/live/initrd.img boot=live union=overlay fetch=$CLONEZILLA_MNT_URL/live/filesystem.squashfs username=user config components quiet noswap edd=on nomodeset enforcing=0 noeject locales=en_US.UTF-8 keyboard-layouts=NONE ocs_prerun=\"dhclient -v eth0\" ocs_prerun1=\"sshfs -o ssh_command='sshpass -p $CLONEZILLA_PASSWD ssh' -o cache=yes,allow_other -o StrictHostKeyChecking=no $CLONEZILLA_USER@$NAME_SERVER:$CLONEZILLA_IMAG_DIR /home/partimag\" ocs_live_run=\"ocs-sr -q2 -c -j2 -z9 -i 4096 -sfsck -scs -senc -batch -p reboot savedisk default sda\" ocs_live_extra_param=\"\" ocs_live_batch=\"yes\" vga=788 net.ifnames=0 splash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1

label clonezilla_restore_disk_to_sda
    menu label clonezilla restore disk to sda
    kernel $CLONEZILLA_MNT_URL/live/vmlinuz
    append initrd=$CLONEZILLA_MNT_URL/live/initrd.img boot=live union=overlay fetch=$CLONEZILLA_MNT_URL/live/filesystem.squashfs username=user config components quiet noswap edd=on nomodeset enforcing=0 noeject locales=en_US.UTF-8 keyboard-layouts=NONE ocs_prerun=\"dhclient -v eth0\" ocs_prerun1=\"sshfs -o ssh_command='sshpass -p $CLONEZILLA_PASSWD ssh' -o cache=yes,allow_other -o StrictHostKeyChecking=no $CLONEZILLA_USER@$NAME_SERVER:$CLONEZILLA_IMAG_DIR /home/partimag\" ocs_live_run=\"ocs-sr -g auto -e1 auto -e2 -r -j2 -k1 -icds -scr -batch -p reboot restoredisk default sda\" ocs_live_extra_param=\"\" ocs_live_batch=\"yes\" vga=788 net.ifnames=0 splash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1
">$PXELINUX_DIR/default
            ;; 
        UEFI_munu)
            echo -e \
"#!ipxe
set menu-timeout 5000
:start
set menu-default rhel_install
set base-ip $NAME_SERVER
set base-url http://\${base-ip}
#menu UEFI iPXE Boot Menu -- Client Info:(IP \${net0/ip}, MAC \${net0/mac})
menu UEFI iPXE Boot Menu
item --gap -- Client Info: net0 ( MAC <\${net0/mac}> IP <\${net0/ip}> )
item --gap -- Client Info: net1 ( MAC <\${net1/mac}> IP <\${net1/ip}> )
#item --gap -- Client Info: net2 ( MAC <\${net2/mac}> IP <\${net2/ip}> )
#item --gap -- Client Info: net3 ( MAC <\${net3/mac}> IP <\${net3/ip}> )
#item --gap -- Client Info: net4 ( MAC <\${net4/mac}> IP <\${net4/ip}> )
#item --gap -- Client Info: net5 ( MAC <\${net5/mac}> IP <\${net5/ip}> )
#item --gap -- Client Info: net6 ( MAC <\${net6/mac}> IP <\${net6/ip}> )
#item --gap -- Client Info: net7 ( MAC <\${net7/mac}> IP <\${net7/ip}> )
#item --gap --
item --gap -- ------------------------- Installers ---------------------------
# 菜单的title
item --key c clonezilla_iso (c)clonezilla ISO
item --key b clonezilla_savedisk_sda (b)clonezilla save disk from sda
item --key r clonezilla_restore_disk_sda (r)clonezilla restore disk to sda
item --key h rhel_install (h)RHEL7.1 install
item --gap -- ------------------------- Advanced Options ---------------------------
item --key S shell (S)Drop to iPXE shell
item --key R reboot (R)Reboot
#choose --timeout \${menu-timeout} --default \${menu-default} selected || goto cancel
#goto \${selected}

#choose --default clonezilla --timeout 5000 option && goto \${option}
choose --default \${menu-default} --timeout \${menu-timeout} option && goto \${option}
# 启动菜单 5000ms 后自动选择 shell 条目

# 菜单显示的条目
:failed
echo Booting failed, dropping to shell
goto shell


:shell 
echo Type 'exit' to get the back to the menu
shell
set menu-timeout 30000
set submenu-timeout 0
goto start
shell

:reboot
reboot

:clonezilla_iso
set boot-url \${base-url}/pxefiles/iso
#set boot-url http://\$Server
initrd \${boot-url}/clonezilla.iso
chain \${boot-url}/iso9660_x64.efi
#chain \${boot-url}/pxefiles/memdisk iso raw
boot || goto failed
goto start

:clonezilla_savedisk_sda
set boot-url \${base-url}/pxefiles/iso/clonezilla
kernel \${boot-url}/live/vmlinuz initrd=initrd.img boot=live union=overlay fetch=\${boot-url}/live/filesystem.squashfs username=user config components quiet noswap edd=on nomodeset enforcing=0 noeject locales=en_US.UTF-8 keyboard-layouts=NONE ocs_prerun1=\"sshfs -o ssh_command='sshpass -p $CLONEZILLA_PASSWD ssh' -o cache=yes,allow_other -o StrictHostKeyChecking=no $CLONEZILLA_USER@$NAME_SERVER:$CLONEZILLA_IMAG_DIR /home/partimag\" ocs_live_run=\"ocs-sr -q2 -c -j2 -z9 -i 4096 -sfsck -scs -senc -batch -p reboot savedisk default sda\" ocs_live_extra_param=\"\" ocs_live_batch=\"yes\" vga=788 net.ifnames=0 splash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1
initrd \${boot-url}/live/initrd.img
boot || goto failed

:clonezilla_restore_disk_sda
set boot-url \${base-url}/pxefiles/iso/clonezilla
kernel \${boot-url}/live/vmlinuz initrd=initrd.img boot=live union=overlay fetch=\${boot-url}/live/filesystem.squashfs username=user config components quiet noswap edd=on nomodeset enforcing=0 noeject locales=en_US.UTF-8 keyboard-layouts=NONE ocs_prerun1=\"sshfs -o ssh_command='sshpass -p $CLONEZILLA_PASSWD ssh' -o cache=yes,allow_other -o StrictHostKeyChecking=no $CLONEZILLA_USER@$NAME_SERVER:$CLONEZILLA_IMAG_DIR /home/partimag\" ocs_live_run=\"ocs-sr -g auto -e1 auto -e2 -r -j2 -scr -k1 -icds -batch -p reboot restoredisk default sda\" ocs_live_extra_param=\"\" ocs_live_batch=\"yes\" vga=788 net.ifnames=0 splash i915.blacklist=yes radeonhd.blacklist=yes nouveau.blacklist=yes vmwgfx.enable_fbdev=1
initrd \${boot-url}/live/initrd.img
boot || goto failed

:rhel_install
set boot-url \${base-url}/pxefiles/iso/mnt
kernel \${boot-url}/images/pxeboot/vmlinuz live-installer/net-image=\${boot-url}/LiveOS/squashfs.img
initrd \${boot-url}/images/pxeboot/initrd.img 
#initrd \${boot-url}/images/pxeboot/initrd.img
boot || goto failed
goto start
# 每个条目对应的功能">$PXEBOOT_DIR/UEFI/menu.ipxe; 
            ;;
        default_BIOS_menu)
            clear;
            echo "BIOS default menu select";
            sed -i '/menu default/d' $PXELINUX_DIR/default;
            j=0;
            for i in $(cat $PXELINUX_DIR/default | grep -i "label" | grep -v "menu" | awk '{print $2}');
            do
                echo "[ $j ]  $i";
                menu_list[j]=$i;
                (( j++ ));
            done
            read -rp "enter the default menu number:" choose_legacy_menu;
            sed -i "/${menu_list[$choose_legacy_menu]}/a\    menu default" $PXELINUX_DIR/default;
            ;;
        default_UEFI_menu)
            clear;
            echo "UEFI default menu select";
            sed -i '/set menu-default/d' $PXEBOOT_DIR/UEFI/menu.ipxe;
            j=0;
            for i in $(cat $PXEBOOT_DIR/UEFI/menu.ipxe | grep "^:" | grep -vE "start|failed" | sed 's/^://')
            do
                echo "[ $j ]  $i";
                menu_list[j]=$i;
                (( j++ ));
            done
            read -rp "enter the default menu number:" choose_legacy_menu;
            sed -i "/:start/a\set menu-default ${menu_list[$choose_legacy_menu]}" $PXEBOOT_DIR/UEFI/menu.ipxe;
        ;;
    esac
}

function _services_status() {
    case $1 in 
        dnsmasq) [ $(pidof dnsmasq | wc -l) -gt 0 ] && return 0 || return 1; ;; 
        dhcp) [ $(netstat -aun | grep :67 | wc -l) -gt 0 ] && return 0 || return 1; ;;
        tftp) [ $(netstat -aun | grep :69 | wc -l) -gt 0 ] && return 0 || return 1; ;;
        nginx) [ $(pidof nginx | wc -l) -gt 0 ] && return 0 || return 1; ;;
        http) [ $(netstat -atn | grep :80 | wc -l) -gt 0 ] && return 0 || return 1; ;;
        sshd) [ $(pidof sshd | wc -l) -gt 0 ] && return 0 || return 1; ;;
        ssh) [ $(netstat -atn | grep :22 | wc -l) -gt 0 ] && return 0 || return 1; ;;
    esac
}

function _check_IP() {
    if uname -r | grep -i el7>/dev/null; then
		#redhat
		devname=$(ifconfig -a | grep -i mtu |grep -v lo | awk '{print $1}' | sed 's/:$//')
	else
		#kylin
		devname=$(ifconfig -a | grep -i encap |grep -v lo | cut -d ' ' -f 1)
	fi
	for i in $devname
		do
            if ifconfig $i | grep 'inet ' | grep 10.1.0.5>/dev/null; then
				echo "$i   inet: $(ifconfig $i | grep 'inet ' | awk '{print $2}' | head -1 | cut -d ':' -f 2\
				)   netmask: $(ifconfig $i | grep 'inet '| awk '{print $4}')";
				read -n 1 -rp "\nAre you confirm this ip configure? (y/n)" choose;
                if [ "$choose" == "Y" ] || [ "$choose" == "y" ]; then
					return 0;
				fi
			fi
        done
	j=0;
	printf "\n";
	for i in $devname
		do
			printf "[%d]\t%s\tinet: %15s\t%s\n" $j $i $(ifconfig $i | grep 'inet ' | awk '{print $2}' |\
			head -1 | cut -d ':' -f 2) $(ethtool $i 2>/dev/null | grep -i speed | cut -d " " -f 2);
			devlist[$j]=$i;
			(( j++ ));
		done
		read -rp "\nplease enter a number to set interface IP:" number;
		ifconfig "${devlist[$number]}:10" 10.1.0.5 netmask 255.255.255.0;
	
}

function _monitor() {
    local main_menu;
    local choose;
    local dnsmasq dhcp tftp nginx http sshd ssh;
    local images disk;
    local ip_addrs client_number;

    local BIOS_default_menu UEFI_default_menu;

    while :
    do
        #sleep 1;
        if _services_status dnsmasq; then dnsmasq=0; else dnsmasq=1; fi
        if _services_status dhcp; then dhcp=0; else dhcp=1; fi
        if _services_status tftp; then tftp=0; else tftp=1; fi
        if _services_status nginx; then nginx=0; else nginx=1; fi
        if _services_status http; then http=0; else http=1; fi
        if _services_status sshd; then sshd=0; else sshd=1; fi
        if _services_status ssh; then ssh=0; else ssh=1; fi
        #容量检查
        images=$(du -sh $CLONEZILLA_IMAG_DIR | awk '{print $1}' || echo "0G") ;
        images=${images:-0G};
        disk=$(df -h / |awk '/\//{print $4}');
        #客户端数量及IP
        ip_addrs=$(netstat -atn |grep -E "$NAME_SERVER:80|$NAME_SERVER:22" | awk '{print $5}' | cut -f 1 -d ":" | sort |uniq);
        #declare -a ip_addrs;
        client_number=$(netstat -atn |grep -E "$NAME_SERVER:80|$NAME_SERVER:22" | awk '{print $5}' | cut -f 1 -d ":" | sort|uniq| wc -l);
        #默认菜单检查
        BIOS_default_menu=$(cat $PXELINUX_DIR/default | grep -C 2 "menu default" | grep "menu label" | sed 's/menu label//' | sed 's/^ *//');
        UEFI_default_menu=$(cat $PXEBOOT_DIR/UEFI/menu.ipxe | grep "set menu-default" | sed 's/set menu-default//'|sed 's/^ *//');
        #########################  display  #########################
        clear;
        echo "                      iPXE system controler"
        printf "STATUS:    "
        if [ $dnsmasq -eq 0 ]; then _green "DNSMASQ    "; else _red "DNSMASQ    "; fi
        if [ $dhcp -eq 0 ]; then _green "DHCP    "; else _red "DHCP    "; fi
        if [ $tftp -eq 0 ]; then _green "TFTP    "; else _red "TFTP    "; fi
        if [ $nginx -eq 0 ]; then _green "NGINX    "; else _red "NGINX    "; fi
        if [ $http -eq 0 ]; then _green "HTTP    "; else _red "HTTP    "; fi
        if [ $sshd -eq 0 ]; then _green "SSHD    "; else _red "SSHD    "; fi
        if [ $ssh -eq 0 ]; then _green "SSHD    "; else _red "SSHD    "; fi
        printf "\n"
        printf "imag size: %s;   disk free: %s;\n" $images $disk ;
        # echo "default munu: ${menu_list[$choose_legacy_menu]}";
        printf "\ndefault BIOS menu: "; _magenta "$BIOS_default_menu";
        printf "\ndefault UEFI menu: "; _magenta "$UEFI_default_menu";
        printf "\n"
        echo "============================  clients: $client_number ================================";
        printf "IP\t\tSTATUS\n"

        for i in $ip_addrs; do
            echo "$i" ;
        done
        # netstat -atn |grep $NAME_SERVER:80;
        # netstat -atn |grep $NAME_SERVER:22;
        # netstat -aun |grep :67;
        # netstat -aun |grep :69;
        [ -f $LOG_FILE_NAME ] &&\
        { echo "==============================   log   ==================================";\
        tail -n 3 $LOG_FILE_NAME;};
        printf "============================== Options =================================="
        printf "\n[ i ] install services  [ d ] start/stop dnsmasq  [ r ] reboot all"
        printf "\n[ u ] remove services   [ n ] start/stop nginx    [ m ] set default munu"
        printf "\n[ q ] quit"
        printf "\n>"
        read -t 0.01 -n 1 -sr main_menu;
        case $main_menu in
            q|Q) exit 0; ;;
            d|D) if [ $dnsmasq -eq 0 ]; then _dnsmasq stop; else _dnsmasq start; fi;;
            n|N) if [ $nginx -eq 0 ]; then _nginx stop; else _nginx start; fi;;
            i|I) 
                printf "\n";
            	read -n 1 -rp "\nAre you shure to install dnsmasq and nginx? (y/n)" choose;
                if [ "$choose" == "Y" ] || [ "$choose" == "y" ]; then
                    _dnsmasq install;
                    _dnsmasq conf;
                    # _dnsmasq interface;
                    _dnsmasq start;

                    _nginx install;
                    _nginx conf;
                    _nginx start;
                    # _nginx stop

                    _ipxe Legacy_boot;
                    _ipxe UEFI_boot;
                    _ipxe clonezilla_conf;
                    _ipxe Legacy_menu;
                    _ipxe UEFI_munu;
                    sleep 1;
                fi
                ;;
            u|U)
                printf "\n";
                read -n 1 -rp "Are you shure to remove dnsmasq and nginx? (y/n)" choose;
                if [ "$choose" == "Y" ] || [ "$choose" == "y" ]; then
                    _dnsmasq stop;
                    _dnsmasq uninstall;
                    _nginx stop;
                    _nginx uninstall;
                    umount $CLONEZILLA_MNT_DIR $ISO_MNT_DIR;
                    userdel -r $CLONEZILLA_USER;
                    rm -rf $LOG_DIR $WWWROOT_DIR $PXEBOOT_DIR;
                    printf "\n";
                    read -n 1 -rp "Are you shure to remove clonwzilla images? (y/n)" choose;
                    if [ "$choose" == "Y" ] || [ "$choose" == "y" ]; then
                        rm -rf $CLONEZILLA_IMAG_DIR;
                    fi
                    #sleep 1;
                fi
                ;;
            r|R) 
                _ipxe UEFI_munu;
                
                ;;
            m|M) 
                clear;
                _ipxe default_BIOS_menu;
                _ipxe default_UEFI_menu;
                #sleep 3;
            ;;
        esac
        sleep 0.5;
    done
}

#####################   MAIN   ####################
# _dnsmasq install
# _dnsmasq conf
# _dnsmasq interface
# _dnsmasq restart

# _nginx install
# _nginx conf
# _nginx restart
# _nginx stop

# _ipxe Legacy_boot
# _ipxe UEFI_boot
# _ipxe Legacy_menu
# _dnsmasq stop
# _dnsmasq uninstall
_check_IP;
_monitor;