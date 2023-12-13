#!/bin/sh

# ---------------------------------------------
# |    VPNC-ON-OWRT v.0.3 - (c)2023 suuhm     |
# |    ----------------------------------     |
# |     FOR TPLINK WR8XX LOW RAM DEVICES      |
# ---------------------------------------------

#
# https://openwrt.org/packages/pkgdata/libgnutls
# https://meefik.github.io/2018/04/21/openwrt-openvpn-4mb-rom/
# https://www.sebastianklein.de/blog/vpn-zwischen-lede-openwrt-und-fritzbox-via-luci/
# https://michael.stapelberg.ch/posts/2009-01-11-openwrt_vpn/
#
# MTU 1380
# IKE DH GROUP dh2
# PFS nopfs
# iptables -I FORWARD -i wg0 -o br-wlanadmin -m conntrack --ctstate ESTABLISHED,RELATED
# iptables -A FORWARD -i br-wlanadmin -o wg0 -j ACCEPT
#


echo "  ---------------------------------------------"
echo "  |    VPNC-ON-OWRT v.0.3 - (c)2023 suuhm     |"
echo "  |    ----------------------------------     |"
echo "  |     FOR TPLINK WR8XX LOW RAM DEVICES      |"
echo "  ---------------------------------------------"
echo; sleep 1


tsh() {
    # Restart services
    service log restart; service network restart; sleep 10

    # Log and status
    logread -e $1; netstat -l -n -p | grep -e "^udp\s.*\s-$"

    # Runtime configuration
    pgrep -f -a wg; wg show; wg showconf $1
    ip address show; ip route show table all
    ip rule show; ip -6 rule show; nft list ruleset

    # Persistent configuration
    uci show network; uci show firewall; crontab -l

    echo; traceroute -4 1.1.1.1
}


kill_switch() {
    cat << EOF > /etc/hotplug.d/iface/99-prevent-leak
#!/bin/sh
if [ "\$ACTION" = ifup ] && (ip a s $1 up) && (iptables -C forwarding_rule -j REJECT); then
    iptables -D forwarding_rule -j REJECT
fi

if [ "\$ACTION" = ifdown ] && (! ip a s $1 up) && (! iptables -C forwarding_rule -j REJECT); then
    iptables -I forwarding_rule -j REJECT
fi
EOF
}


keeping_alives() {
    n=10
    #ping n -t
}


check_ip() {
    echo "[+] Get IP and Trace-routingcheck:"; echo; sleep 1
    echo "My IP is: $(wget -qO- http://ifconfig.co | grep "class=\"ip" | sed "s/.*class=\"ip\">\(.*\)<\/code.*/\1/g")"; echo
    mtr -r -c3 1.1.1.1 
}

_create_systemv_script(){

  echo; echo "Setup LD_Path and Path for libs and bins."; sleep 2
  sed 's/PATH="\/usr\/sbin:\/usr\/bin:\/sbin:\/bin"$/PATH="\/usr\/sbin:\/usr\/bin:\/sbin:\/bin:\/tmp\/usr\/sbin"\nexport LD_LIBRARY_PATH="\/tmp\/usr\/lib"/g' \
  -i /etc/profile
  #export LD_LIBRARY_PATH=/tmp/usr/lib

  echo; echo "Create init script..."; sleep 2

  cat <<EOF >/etc/init.d/owrt-vpnc
#!/bin/sh /etc/rc.common

#
# opkg update ; opkg install kmod-tun
# python -m http.server -b 0.0.0.0 442
# wget http://... / configs/

#

START=99

. /etc/profile

install_pkg() {
  tar xzf \$(opkg download \$1 |grep Downloaded |cut -d\  -f4 |sed '\$s/.$//')
  tar xzf data.tar.gz
  echo; echo "Cleanup some stuff..."
  rm -f *.ipk control.tar.gz data.tar.gz debian-binary
}

install() {
  cd /tmp
  command opkg update || exit 1
  for p in vpnc libgpg-error libgcrypt libgnutls libgmp libatomic libnettle vpnc-scripts luci-proto-vpnc resolveip; do
     echo "[+] Installing packet \$p.."; echo
     install_pkg \$p
  done
  #install_pkg libopenssl
  #install_pkg liblzo

  # if using luci plugin..
  cp -r /usr/lib/lua/luci/model/* /usr/lib/lua/luci/model/
  rm -rf /tmp/luci-* && /etc/init.d/uhttpd restart 
  #/etc/init.d/rpcd restart
}

start () {
  if [ -z "\$(which vpnc)" ]
  then
    # fix out memory fault error
    sysctl -w vm.overcommit_memory=1
    sleep 10
    install
  fi
  echo; echo "Startup VPNC:"; echo; sleep 2
  CONFILE=/root/th01.conf
  ln -s /tmp/etc/vpnc /etc/
  ln -s /tmp/lib/netifd/vpnc-script /etc/vpnc/
  command vpnc \$CONFILE
  #set ip - routing
  IP=\$(ping -4 -q -w1 -c1 \$(grep "^IP.*gateway" \$CONFILE | cut -d " " -f3) | grep PING | sed 's/PING .** (\([^)]*\)).*/\1/g')
  VIAR=\$(ip r | grep default | cut -d " " -f3)
  IP_PR=\$(ip r | grep tun | cut -d " " -f9)
  #IP_PR=192.168.178.206

  ip a a \${IP_PR}/24 dev tun0
  ip link set mtu 1380 up dev tun0

  # Redirecting Gateway
  iptables -I FORWARD -o tun+ -j ACCEPT
  iptables -I OUTPUT -o tun+ -j ACCEPT
  iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
  ip r a \$IP via \$VIAR dev br-wan
  ip r a 0.0.0.0/1 via \$IP_PR dev tun0 
  ip r a 128.0.0.0/1 via \$IP_PR dev tun0
  #ip r a 0.0.0.0/1 via 192.168.178.2 dev tun0 proto static src 192.168.178.206
  #ip r a 128.0.0.0/1 via 192.168.178.2 dev tun0 proto static src 192.168.178.206

}

stop() {
  PIDOF=\$(ps |egrep vpnc |egrep  -v grep |awk '{print \$1}')
  kill \${PIDOF}
  vpnc-disconnect

  #delete routes
  iptables -D FORWARD -o tun+ -j ACCEPT
  iptables -D OUTPUT -o tun+ -j ACCEPT
  iptables -t nat -D POSTROUTING -o tun0 -j MASQUERADE
  ip r d \$IP via \$VIAR dev br-wan
  ip r d 0.0.0.0/1 via \$IP_PR dev tun0 
  ip r d 128.0.0.0/1 via \$IP_PR dev tun0
}
EOF

  echo; echo "Done.. Now Enable script.."; sleep 2
  chmod +x /etc/init.d/owrt-vpnc
  /etc/init.d/owrt-vpnc enable

  # Create Custom Interface: tun0
  # Firewall Settings:
  # -----------------

  # General Settings
  # ---------------
  # Input: reject
  # Output: accept
  # Forward: reject
  # Masquerading: checked
  # MSS clamping: checked
  # Covered networks: vpn

  # Inter-Zone Forwarding
  # Allow forward from source zones: lan
}

set_fw_routing() {
  cat << EOF >> /etc/config/firewall

config zone
      option name 'vpncfw'
      option input 'REJECT'
      option output 'ACCEPT'
      option forward 'REJECT'
      option masq '1'
      option mtu_fix '1'
      list network 'IPSEC_NET'

config forwarding
      option src 'mynet'
      option dest 'vpncfw'
EOF


  ##cat << EOF >> /etc/config/network

}

create_hp_button() {
  # ON PRESS: WPS/RESET Button
  # --------------------------

  # Create directory and script: 
  mkdir -p /etc/hotplug.d/button 2> /dev/null

  cat << EOF > /etc/hotplug.d/button/30-vpnc
#!/bin/sh
# for debugging button name and action name, uncomment this 2 lines
logger $BUTTON
logger $ACTION

if [ "$ACTION" = "pressed" -a "$BUTTON" = "reset" ]; then
    /etc/init.d/owrt-vpnc start
fi
EOF


  # FALLBACK RC-- VERSION 11-14 ?
  #
  cat << EOF > /etc/button.rc/reset
#!/bin/sh

. /lib/functions.sh

OVERLAY="$( grep ' /overlay ' /proc/mounts )"

case "$ACTION" in
pressed)
        [ -z "$OVERLAY" ] && return 0

        return 5
;;
timeout)
        . /etc/diag.sh
        set_state failsafe
;;
released)
        if [ "$SEEN" -lt 1 ]; then
                logger "STARTING VPNC..."
                /etc/init.d/owrt-vpnc restart
                sleep 7; logger "My IP is: $(wget -qO- http://ifconfig.co | grep "class=\"ip" | sed "s/.*class=\"ip\">\(.*\)<\/code.*/\1/g")"
                logger "VPNC RESTART Done."
        elif [ "$SEEN" -ge 5 -a -n "$OVERLAY" ]
        then
                echo "REBOOT" > /dev/console
                sync
                reboot
        elif [ "$SEEN" -ge 10 -a -n "$OVERLAY" ]
        then
                echo "FACTORY RESET" > /dev/console
                jffs2reset -y && reboot &
        fi
;;
esac

return 0
EOF
}


_main() {

    if [[ "$1" == "--install-script" ]]; then
        _create_systemv_script
    elif [[ "$1" == "--set-fw-routing" ]]; then
        set_fw_routing
    elif [[ "$1" == "--setup-button" ]]; then
        create_hp_button
    elif [[ "$1" == "--ipcheck" ]]; then
        check_ip ; exit 0;
    elif [[ "$1" == "--debugging" ]]; then
        tsh $2; exit 0;
    else
        echo "Usage: $0 <--install-script | --setup-fw-routing | --setup-button | --ipcheck | --debugging>"
        exit 2;
    fi

echo;echo "[***] Done"; echo
wg show

}

_main $1 $2 $3

exit 0
