#!/bin/sh
#
#
# WG-QUICK-OWRT v.01 - (c)2023 suuhm 
# ---------------------------------- 
# FOR TPLINK WR8XX LOW RAM DEVICES (4/32)
#

# https://ubuntu.com/server/docs/wireguard-vpn-defaultgw
# https://openwrt.org/docs/guide-user/network/wifi/dumbap
#
# Create bridge WIFIAP (10.55.55.0/24) ==> LAN
# VPNC config
#

# ALLOW PING ECHO: iptables -I OUTPUT -p icmp -j ACCEPT 

echo "  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
echo "  |    WG-QUICK-OWRT v.01 - (c)2023 suuhm     |"
echo "  |    ----------------------------------     |"
echo "  |     FOR TPLINK WR8XX LOW RAM DEVICES      |"
echo "  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒"
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


create_hp_button() {
    cat << EOF > /etc/rc.button/rfkill
#!/bin/sh
[ "\${ACTION}" = "released" -o -n "\${TYPE}" ] || exit 0
. /lib/functions.sh
if [ "\$ACTION" = "released" ]; then
     logger \$BUTTON
     logger \$ACTION
     wg-setup --down wg0 ; wg-setup.sh --manual /etc/wireguard/wg0.conf wg0
     logger "Done -> WG RESET"
     return 0
fi
EOF
}


keeping_alives() {
    n=10
    while sleep 50; do
        t=$(ping -c $n 9.9.9.9 | grep -o -E '[0-9]+ packets r' | grep -o -E '[0-9]+')
        if [ "$t" -eq 0 ]; then
            /etc/init.d/wg0 restart
        fi
    done
}


check_ip() {
    echo "[+] Get IP and Trace-routingcheck:"; echo; sleep 1
    echo "My IP is: $(wget -qO- http://ifconfig.co | grep "class=\"ip" | sed "s/.*class=\"ip\">\(.*\)<\/code.*/\1/g")"; echo
    mtr -r -c3 1.1.1.1 
}


create_manual() {

    devname=$2
    tunnle_fwmark="55555"
    EP=$(grep -E "^Endpo" $1  | cut -d ' ' -f3 | cut -d ':' -f1)
    EPPORT=$(grep -E "^Endpo" $1  | cut -d ' ' -f3 | cut -d ':' -f2)
    EP_4=$(ping -4 -q -w1 -c1 $EP | grep PING | sed 's/PING .** (\([^)]*\)).*/\1/g'):$EPPORT
    myipsub="$(grep Addre $1 | cut -d ' ' -f3)"
    mydns="$(grep DNS $1 | head -n1 | cut -d ' ' -f3)"

    echo "[+] Add device $devname as wireguard dev with Endpoint $EP_4 ..."; sleep 2
    ip link add $devname type wireguard
    ip link set mtu 1420 up dev $devname

    if [[ "$2" == "--static-add" ]]; then
        echo "CCCCCCCbbbbbbbbbeeeeeeeeeffffffffffgggggggg="> $devname.priv
        echo "aaaaaaabbbbbbbbbeeeeeeeeeffffffffffgggggggg="> $devname.pskey
        wg set $devname private-key $devname.priv peer bbbaaaabbbbbbbbbbeeeeeeeeeffffffffffgggggggg= preshared-key $devname.pskey allowed-ips 192.168.178.0/24,0.0.0.0/0 endpoint $EP persistent-keepalive 25
    else
        conffile=/tmp/$devname.temp
        cp -a $1 $conffile
        sed "s/^Endpoint.*$/Endpoint = $EP_4/; s/^Addr/#Addr/g; s/^DNS/#DNS/g" -i $conffile
        wg setconf $devname $conffile
        #wg set $devname endpoint $EP_4
    fi

    #
    # echo "wg set wg0 $(cat *.config | grep "=" | sed ':a;N;$!ba; s/\n/ /g; s/ = / /g')"
    echo "[+] Setup IP Address/Policies and Routes..."; echo; sleep 2

    # Check for min CIDR /24 subnetsize:
    if [ `grep Addr $conffile | head -n1 | cut -d ' ' -f3 | cut -d '/' -f2` -ge 32 ]; then
        myipsub=$(echo $myipsub | sed 's/\/\d\d/\/24/')
    fi
    ip addr add $myipsub dev $devname

    # Setup Routing - fwmark policy:
    # ------------------------------
    #ip r del default ; ip route replace default via $(ip r | grep default | cut -d " " -f3,4,5,6,7,8,9) metric 100
    #ip r del default via $(ip r | grep default | head -n1 | cut -d " " -f3,4,5,6,7,8,9)

    echo "[-] Cleanup old Routes & Policies..."; echo; sleep 2
    iptables -D FORWARD -o $devname -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -o $devname -j SNAT --to-source $(echo $myipsub | cut -d '/' -f1 2>/dev/null)
    ip -4 route del 0.0.0.0/0 dev $devname table $tunnle_fwmark 2>/dev/null
    #TODO: buddy when deleting maintable and twice suppress_pref* 
    #while ip rule delete not from all 2>/dev/null || ip ru d from all lookup main suppress_prefixlength 0 2>/dev/null; do 
    #    true; 
    #done

    # Setup policy:
    # ------------
    # https://ro-che.info/articles/2021-02-27-linux-routing

    wg set $devname fwmark $tunnle_fwmark
    ip -4 route add 0.0.0.0/0 dev $devname table $tunnle_fwmark

    # Route all packets fw_marked via table except the peer-encapsualted ones:
    ip -4 rule add not fwmark $tunnle_fwmark table $tunnle_fwmark
    # Respect all manual added routes in main otherwise go next (ip ru s):
    ip -4 rule add table main suppress_prefixlength 0
    # https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html
    sysctl -q net.ipv4.conf.all.src_valid_mark=1

    #iptables -I FORWARD -o wg+ -j ACCEPT
    iptables -I FORWARD -o $devname -j ACCEPT
    iptables -t nat -A POSTROUTING -o $devname -j SNAT --to-source $(echo $myipsub | cut -d '/' -f1)
    #iptables -t nat -I POSTROUTING -o $devname -j MASQUERADE

    # Show policy and fwmarks:
    ip rule list; echo; ip r show; echo; ip route list table $tunnle_fwmark

    #IPV6
    #ip addr add <redacted_ipv6>/128 dev $devname
    #ip route add ::/0 dev test0

    # LOADBALANCING => via IP || dev DEVICE
    # iproute2 - command: tc
    # ip route add default scope global nexthop via 192.168.0.254 nexthop via 192.168.1.254
    # ip route add default scope global nexthop dev ppp0 weight 100 nexthop dev ppp1 weight 100

    # RELAY
    # iptables -t mangle -A PREROUTING -p tcp -m multiport --dport 80,443 -j MARK --set-mark 0x80
    # echo "80  web" >> /etc/iproute2/rt_tables
    # ip rule add fwmark 0x80 table web
    # ip route add default via 192.168.0.254 table web
}


create_uci() {

    # Install packages
    opkg update
    opkg install wireguard-tools

    # Configuration parameters
    VPN_IF="vpn"
    VPN_PORT="51820"
    VPN_ADDR="192.168.9.1/24"
    VPN_ADDR6="fd00:9::1/64"

    #
    # Generate keys
    umask go=
    wg genkey | tee wgserver.key | wg pubkey > wgserver.pub
    wg genkey | tee wgclient.key | wg pubkey > wgclient.pub
    wg genpsk > wgclient.psk

    # Server private key
    VPN_KEY="$(cat wgserver.key)"

    # Pre-shared key
    VPN_PSK="$(cat wgclient.psk)"

    # Client public key
    VPN_PUB="$(cat wgclient.pub)"

    #
    # Configure firewall
    uci rename firewall.@zone[0]="lan"
    uci rename firewall.@zone[1]="wan"
    uci del_list firewall.lan.network="${VPN_IF}"
    uci add_list firewall.lan.network="${VPN_IF}"
    uci -q delete firewall.wg
    uci set firewall.wg="rule"
    uci set firewall.wg.name="Allow-WireGuard"
    uci set firewall.wg.src="wan"
    uci set firewall.wg.dest_port="${VPN_PORT}"
    uci set firewall.wg.proto="udp"
    uci set firewall.wg.target="ACCEPT"
    uci commit firewall
    service firewall restart

    # Configure network
    uci -q delete network.${VPN_IF}
    uci set network.${VPN_IF}="interface"
    uci set network.${VPN_IF}.proto="wireguard"
    uci set network.${VPN_IF}.private_key="${VPN_KEY}"
    uci set network.${VPN_IF}.listen_port="${VPN_PORT}"
    uci add_list network.${VPN_IF}.addresses="${VPN_ADDR}"
    uci add_list network.${VPN_IF}.addresses="${VPN_ADDR6}"

    # Add VPN peers
    uci -q delete network.wgclient
    uci set network.wgclient="wireguard_${VPN_IF}"
    uci set network.wgclient.public_key="${VPN_PUB}"
    uci set network.wgclient.preshared_key="${VPN_PSK}"
    uci add_list network.wgclient.allowed_ips="${VPN_ADDR%.*}.2/32"
    uci add_list network.wgclient.allowed_ips="${VPN_ADDR6%:*}:2/128"
    uci commit network
    service network restart

    # Configuration parameters
    VPN_IDS="wgserver wgclient wglaptop wgmobile"
    VPN_PKI="."
    VPN_IF="vpn"
    VPN_PORT="$(uci -q get network.${VPN_IF}.listen_port)"
    read -r VPN_ADDR VPN_ADDR6 << EOI
$(uci -q get network.${VPN_IF}.addresses)
EOI

    # Fetch server address
    NET_FQDN="$(uci -q get ddns.@service[0].lookup_host)"
    . /lib/functions/network.sh
    network_flush_cache
    network_find_wan NET_IF
    network_get_ipaddr NET_ADDR "${NET_IF}"
    if [ -n "${NET_FQDN}" ]
    then VPN_SERV="${NET_FQDN}"
    else VPN_SERV="${NET_ADDR}"
    fi

    # Generate client keys
    umask go=
    mkdir -p ${VPN_PKI}
    for VPN_ID in ${VPN_IDS#* }
    do
    wg genkey \
    | tee ${VPN_PKI}/${VPN_ID}.key \
    | wg pubkey > ${VPN_PKI}/${VPN_ID}.pub
    wg genpsk > ${VPN_PKI}/${VPN_ID}.psk
    done

    # Generate client profiles
    VPN_SFX="1"
    for VPN_ID in ${VPN_IDS#* }
    do
    let VPN_SFX++
    cat << EOF > ${VPN_PKI}/${VPN_ID}.conf
[Interface]
Address = ${VPN_ADDR%.*}.${VPN_SFX}/24, ${VPN_ADDR6%:*}:${VPN_SFX}/64
PrivateKey = $(cat ${VPN_PKI}/${VPN_ID}.key)
DNS = ${VPN_ADDR%/*}, ${VPN_ADDR6%/*}
[Peer]
PublicKey = $(cat ${VPN_PKI}/${VPN_IDS%% *}.pub)
PresharedKey = $(cat ${VPN_PKI}/${VPN_ID}.psk)
PersistentKeepalive = 25
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${VPN_SERV}:${VPN_PORT}
EOF
    done
    ls ${VPN_PKI}/*.conf

    # Back up client profiles
    cat << EOF >> /etc/sysupgrade.conf
$(pwd ${VPN_PKI})
EOF

    # Add VPN peers
    VPN_SFX="1"
    for VPN_ID in ${VPN_IDS#* }
    do
    let VPN_SFX++
    uci -q delete network.${VPN_ID}
    uci set network.${VPN_ID}="wireguard_${VPN_IF}"
    uci set network.${VPN_ID}.description="${VPN_ID}"
    uci set network.${VPN_ID}.private_key="$(cat ${VPN_PKI}/${VPN_ID}.key)"
    uci set network.${VPN_ID}.public_key="$(cat ${VPN_PKI}/${VPN_ID}.pub)"
    uci set network.${VPN_ID}.preshared_key="$(cat ${VPN_PKI}/${VPN_ID}.psk)"
    uci add_list network.${VPN_ID}.allowed_ips="${VPN_ADDR%.*}.${VPN_SFX}/32"
    uci add_list network.${VPN_ID}.allowed_ips="${VPN_ADDR6%:*}:${VPN_SFX}/128"
    done
    uci commit network
    service network restart
}

_main() {

    if [[ "$1" == "--manual" ]]; then
        create_manual $2 $3
    elif [[ "$1" == "--auto-uci" ]]; then
        create_uci
    elif [[ "$1" == "--down" ]]; then
        ip link del $2
        exit 0;
    elif [[ "$1" == "--ipcheck" ]]; then
        check_ip ; exit 0;
    elif [[ "$1" == "--create-button" ]]; then
        create_hp_button; exit 0;
    elif [[ "$1" == "--debugging" ]]; then
        tsh $2; exit 0;
    else
        echo "Usage: $0 <--manual <CONFFILE> [--static-add] | --auto-uci | --down | --ipcheck | --create-button | --debugging> <DEVICENAME>"
        exit 2;
    fi

echo;echo "[***] Done"; echo
wg show

}

_main $1 $2 $3
exit 0
