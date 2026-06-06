# SD-WAN Verge OpenWrt/iStoreOS Plugin

This directory contains the first OpenWrt/iStoreOS package skeleton for SD-WAN Verge.

The plugin applies the same half-route idea as the original BAT script, but on the router:

- `0.0.0.0/1 via 192.168.1.140`
- `128.0.0.0/1 via 192.168.1.140`
- optional dnsmasq DNS replacement with `223.5.5.5` and `114.114.114.114`

The LuCI page exposes a mode selector:

- `Half Route`: the stable default. It uses OpenWrt/iStoreOS kernel routing and keeps source IP unchanged.
- `TUN`: calls a configured real TUN backend. The package checks `kmod-tun` through `/dev/net/tun` and checks that the backend file is executable before starting. If either dependency is missing, it refuses to start instead of pretending to accelerate traffic.

The LuCI page also shows traffic counters and 常用网站检测 results for Google, YouTube, Claude, Amazon, GitHub, and OpenAI. Site tests use IPv4 `curl` connection timing because the target CPE scenario is IPv4-only.

TUN 模式必须接入真实 TUN backend；这个插件只负责配置、依赖检查和生命周期管理。

Installing the package does not enable acceleration by itself. The default UCI switch is disabled, so the router does not change routes or DNS until the user starts it.

## Layout

```text
router/openwrt/
  Makefile
  files/etc/config/sdwan_verge
  files/etc/init.d/sdwan-verge
  files/usr/libexec/sdwan-verge/sdwan-verge-core
  files/usr/share/luci/menu.d/luci-app-sdwan-verge.json
  files/usr/share/rpcd/acl.d/luci-app-sdwan-verge.json
  files/www/luci-static/resources/view/sdwan-verge/dashboard.js
  tests/static_test.sh
```

## Build With OpenWrt SDK

Copy this package directory into an OpenWrt SDK package folder:

```sh
mkdir -p package/luci-app-sdwan-verge
cp -R /path/to/sdwan软件/router/openwrt/* package/luci-app-sdwan-verge/
make package/luci-app-sdwan-verge/compile V=s
```

The generated IPK will be under the SDK output package directory for the selected target.

## Build Repo-Local All-Arch IPK

This package contains LuCI JavaScript, shell scripts, and config files only. For quick testing, the repo can produce an `Architecture: all` IPK without the OpenWrt SDK:

```sh
bash scripts/package_openwrt_ipk.sh
```

Output:

```text
dist/releases/luci-app-sdwan-verge_0.1.0-2_all.ipk
```

## Install

```sh
opkg install luci-app-sdwan-verge_0.1.0-2_all.ipk
/etc/init.d/rpcd restart
```

Open LuCI:

```text
Services > SD-WAN Verge
```

## Runtime Commands

```sh
/usr/libexec/sdwan-verge/sdwan-verge-core status
/usr/libexec/sdwan-verge/sdwan-verge-core traffic
/usr/libexec/sdwan-verge/sdwan-verge-core sites
/usr/libexec/sdwan-verge/sdwan-verge-core doctor
/usr/libexec/sdwan-verge/sdwan-verge-core start
/usr/libexec/sdwan-verge/sdwan-verge-core stop
/usr/libexec/sdwan-verge/sdwan-verge-core logs
/usr/libexec/sdwan-verge/sdwan-verge-core uninstall
```

Or through init:

```sh
/etc/init.d/sdwan-verge start
/etc/init.d/sdwan-verge stop
/etc/init.d/sdwan-verge status
```

## Safety Notes

- The OpenWrt/iStoreOS router must be the default gateway for LAN clients if the route change should affect the whole LAN.
- The CPE gateway must be reachable from the router. The default is `192.168.1.140`.
- `start` replaces two half routes in Half Route mode, or calls the configured TUN backend in TUN mode, and optionally replaces dnsmasq DNS servers.
- `stop` deletes the two half routes and restores the saved dnsmasq DNS backup when available.
- If DNS backup is missing, `stop` clears the dnsmasq server list and restarts dnsmasq.
- TUN mode requires a real executable backend at the configured path, for example `/usr/libexec/sdwan-verge/sdwan-verge-tun`. The backend contract is:

```sh
sdwan-verge-tun start <interface> <cpe_gateway>
sdwan-verge-tun stop <interface> <cpe_gateway>
```

The backend owns packet forwarding. The LuCI plugin owns config, dependency checks, DNS, logs, and status.
- The LuCI page has an uninstall button. It calls `uninstall`, which stops acceleration first and then removes `luci-app-sdwan-verge`.
- Emergency stop:

```sh
/usr/libexec/sdwan-verge/sdwan-verge-core stop
ip route del 0.0.0.0/1 2>/dev/null
ip route del 128.0.0.0/1 2>/dev/null
/etc/init.d/dnsmasq restart
```

## iStoreOS Notes

iStoreOS is OpenWrt-based, so the package layout can be reused. For an iStoreOS release, add the required app metadata, icon, description, architecture target, and repository signing/publishing workflow used by the target iStoreOS channel.
