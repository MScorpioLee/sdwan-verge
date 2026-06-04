# macOS TUN 直连 CPE 真机试用指南

本指南用于在独立测试环境验证 `SD-WAN Verge` 的 macOS utun 直连 CPE 模式。

## 当前交付状态

已在 Codex 侧完成：

- macOS helper 可编译。
- helper `self-test` 覆盖：
  - IPv4 checksum。
  - UDP NAT 出向和回程改写。
  - 以太帧封装，目的 MAC 指向 CPE。
  - 连续 3 次健康失败计数逻辑。
  - 半路由和 CPE 防回环路由的 plan 输出。
- Flutter macOS `sdwan_client/tun` channel 已接 helper。
- macOS app release 可编译。

未在 Codex 侧执行：

- 未运行 helper `start`。
- 未添加 `0.0.0.0/1` 或 `128.0.0.0/1` 半路由。
- 未修改默认网关、DNS 或物理网卡配置。
- 未做真实流量经 utun -> CPE 出口验证。

## 试用前准备

建议在独立测试 Mac 或可断网恢复的测试网络中执行。CPE 地址默认是：

```sh
192.168.1.140
```

试用前记录当前网络状态：

```sh
route -n get default
netstat -rn
networksetup -listallnetworkservices
networksetup -getdnsservers Wi-Fi
```

如果实际物理网卡不是 `Wi-Fi`，请把最后一条替换成你的网络服务名。

## 安装和启动

解压 macOS 包后打开 `SD-WAN Verge.app`。

点击：

```text
开启 TUN
```

macOS 会弹出管理员授权。授权后 helper 会执行：

```sh
ifconfig utunX inet 10.255.0.2 10.255.0.1 mtu 1500 up
route -n add -host 192.168.1.140 -interface <物理网卡>
route -n add 0.0.0.0/1 -interface utunX
route -n add 128.0.0.0/1 -interface utunX
```

`192.168.1.140/32` 的更具体路由用于防止发往 CPE 的包再次被 utun 截获。

## 成功观察点

查看 helper/app 状态：

```sh
/Applications/SD-WAN\ Verge.app/Contents/Resources/sdwan-macos-helper status
```

查看路由：

```sh
netstat -rn | grep -E '0/1|128.0/1|192.168.1.140|utun'
```

观察是否有发往 CPE 的物理网卡流量：

```sh
sudo tcpdump -i en0 host 192.168.1.140
```

如果你的物理网卡不是 `en0`，请替换成实际接口。

查看公网出口：

```sh
curl -4 https://ifconfig.me
```

建议对比：

1. 关闭 TUN 时的出口 IP。
2. 开启 TUN 后的出口 IP。
3. CPE 管理端或上游出口看到的连接来源。

## 自动回退验证

仅在独立测试环境执行。

1. 开启 TUN。
2. 让 CPE `192.168.1.140` 临时不可达，例如拔掉测试 CPE 网线或停掉测试 CPE LAN 口。
3. 等待约 15 秒以上。
4. App 应显示：

```text
CPE 异常，已自动回切直连
```

5. 检查半路由应被删除：

```sh
netstat -rn | grep -E '0/1|128.0/1'
```

## 正常关闭

在 App 中点击：

```text
关闭 TUN
```

或手动执行：

```sh
sudo /Applications/SD-WAN\ Verge.app/Contents/Resources/sdwan-macos-helper stop
```

## 断网急救命令

如果 App 或 helper 异常退出后网络不通，在终端执行：

```sh
sudo route delete 0.0.0.0/1
sudo route delete 128.0.0.0/1
sudo route delete 192.168.1.140
sudo pkill -f sdwan-macos-helper
```

如果仍未恢复，按试用前快照恢复网关和 DNS，或重启网络服务：

```sh
sudo ifconfig en0 down
sudo ifconfig en0 up
```

`en0` 请替换为你的实际物理网卡。

## 重要说明

本版本不是代理模式，不依赖 SOCKS/HTTP，也不假设 CPE 有隧道入口。数据面按三层旁路由语义工作：

```text
App 流量 -> utun -> helper NAT/BPF -> 物理网卡 -> CPE MAC -> CPE 转发公网
```

Codex 侧已完成编译和非破坏性逻辑自检；真实链路是否成功，必须以独立环境中的 `tcpdump`、出口 IP、CPE 侧观测为准。

