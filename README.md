# wg-vpnc-4_32
Running vpnc and wireguard on small embedded devices with openwrt firmware (4/32 warning)

> [!NOTE]
> https://openwrt.org/supported_devices/432_warning


## Features

- Running wireguard on small routers like TP-Link WR841
- Running VPNC on small routers like TP-Link WR841
- Includes install and config scripting
- Setup hotplug buttons on back of your devices

## How to use

1. Clone the script via
```bash
git clone https://github.com/suuhm/wg-vpnc-4_32 && cd wg-vpnc-4_32
chmod +x *.sh
```

## Y. Run Script WireGuard:
```bash
Usage: ./wg-quick-owrt.sh <--manual <CONFFILE> [--static-add] | --auto-uci | --down | --ipcheck | --create-button | --debugging> <DEVICENAME>
```
### Connect as Client with WireGuard Server:

### Optional when the openwrt fw is to big:
copy .config file to your openWRT source dir and run:

```bash
./scripts/feeds update -a && ./scripts/feeds install -a
make -j4 V=sc
scp target/linux/generic/<IMAGEFILE> root@device:/tmp/
#sysupgrade run
```

### Else, simply run:
```bash
opkg update ; opkg install wireguard wireguard-tools
```

Now run on device simply the config file you got from the server e.g:
```bash
./wg-quick-owrt.sh --manual /home/user/wg0.conf wg0
```

## X. Run Script VPNC:
```bash
Usage: ./setup-vpnc-owrt.sh <--install-script | --setup-fw-routing | --setup-button | --ipcheck | --debugging>
```



> [!IMPORTANT]
> Please report bugs and issues! 
