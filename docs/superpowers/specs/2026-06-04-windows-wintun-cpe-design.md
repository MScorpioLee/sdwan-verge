# Windows Wintun CPE TUN 设计

日期：2026-06-04

## 结论

Windows 可以按 macOS 已验证通过的思路做真实 TUN，但不能只接 `Wintun`。

macOS 当前可用链路是：

```text
App -> root helper -> utun -> 用户态 NAT -> BPF 物理网卡注入 -> CPE
                                      <- BPF 捕获回程 <- CPE
```

Windows 等价链路应为：

```text
App -> Windows service/helper -> Wintun -> 用户态 NAT -> WinDivert/WFP 注入 -> CPE
                                                 <- WinDivert/WFP 捕获回程 <- CPE
```

`Wintun` 只负责虚拟网卡和 IP 包读写。它不负责把包转发到 CPE，也不负责拦截回程包。若只创建 Wintun 并添加默认路由，流量会进入虚拟网卡后黑洞。

## 官方能力依据

- Wintun 是 Windows 的 Layer 3 TUN driver，应用可通过 `wintun.dll` 创建 adapter、启动 session，并通过 `WintunReceivePacket` / `WintunSendPacket` 读写 IP 包。
- WinDivert 可在用户态捕获、修改、丢弃、重新注入 Windows 网络栈数据包，文档明确其可用于 NAT、VPN、tunneling 应用。

## 设计目标

1. Windows 也采用 TUN 优先，不回退到 route/DNS 主模式。
2. App 日常开关不反复 UAC；首次安装 helper/service 时需要管理员授权。
3. 数据面真实转发，不出现“虚拟网卡已开但流量黑洞”。
4. CPE 异常连续失败时自动拆路由、停止 Wintun session、恢复直连。
5. 状态、日志、连接列表、流量统计继续走现有 Flutter `sdwan_client/tun` channel。

## 架构组件

### Flutter App

- 继续作为前台控制面。
- `start/stop/status/healthCheck/logs/connections` 调用 Windows helper/service。
- 不直接创建 Wintun，不直接安装驱动。

### Windows Service

服务名建议：`SDWANVergeService`

职责：

- 管理 Wintun adapter 生命周期。
- 管理 WinDivert 或 WFP 数据面。
- 写状态文件或提供本地 IPC。
- 崩溃/退出时执行 cleanup。
- 负责一次性安装/卸载。

### Wintun Adapter

固定 adapter 名：`SD-WAN Verge`

职责：

- 创建 Layer 3 虚拟网卡。
- 设置 TUN 地址，例如 `10.255.0.2/30`。
- 设置 DNS 指向 CPE 或用户配置的 DNS。
- 添加系统半路由到 Wintun：`0.0.0.0/1` 和 `128.0.0.0/1`。

### WinDivert/WFP 数据面

职责：

- 对从 Wintun 读到的出站 IP 包做 SNAT。
- 使用专用源端口池，避免和本机真实连接冲突。
- 将 NAT 后的包从物理网卡方向注入，并确保下一跳为 CPE。
- 捕获回程包，阻止 Windows TCP/IP 栈对这些包发 RST。
- 反向 NAT 后写回 Wintun。

## 防回环策略

Windows 需要两类路由：

1. 发往 CPE 的更具体直连路由：

```text
192.168.1.140/32 -> physical interface
```

2. 应用流量进 Wintun：

```text
0.0.0.0/1 -> Wintun
128.0.0.0/1 -> Wintun
```

注入 NAT 后公网包时，数据面必须避开 Wintun 路由，走物理网卡到 CPE。优先实现：

- WinDivert `WINDIVERT_LAYER_NETWORK` 注入；
- 设置正确的 outbound/inbound 方向；
- 使用物理网卡 IfIdx/SubIfIdx；
- 对注入包做 checksum 重算；
- 过滤 impostor/loopback，避免自捕获死循环。

若 WinDivert 的接口控制在实测中不稳定，备选是 WFP callout 或 NDIS lightweight filter；但这会显著增加驱动开发和签名复杂度。

## NAT 规则

出站：

```text
src = 10.255.0.2:client_port
dst = public_ip:dst_port

改写为：

src = physical_ip:reserved_port
dst = public_ip:dst_port
```

维护连接表：

```text
proto + physical_ip:reserved_port + dst_ip:dst_port
  -> tun_ip:client_port + dst_ip:dst_port
```

回程：

```text
src = public_ip:dst_port
dst = physical_ip:reserved_port

改写为：

src = public_ip:dst_port
dst = 10.255.0.2:client_port
```

然后通过 `WintunSendPacket` 写回虚拟网卡。

## 健康检测与回退

启动前：

- L1：ping/TCP 探测 CPE `192.168.1.140`。
- L3：通过数据面发一个小型 UDP/TCP 探测，确认经 CPE 出口可用。

运行中：

- 连续 3 次失败自动停止。
- 删除 Wintun 半路由。
- 关闭 Wintun session。
- 关闭 WinDivert handle。
- UI 显示“CPE 异常，已自动回切直连”。

## 打包

Windows 产物应为 `.exe` 安装器：

- 安装 Flutter App。
- 安装 Windows service。
- 放置 `wintun.dll`。
- 放置 WinDivert DLL/SYS 或 WFP 组件。
- 安装时请求管理员权限一次。

GitHub Actions artifact 可保留，但 GitHub Release 必须上传 `.exe` 安装器，方便用户直接下载。

## 非目标

本设计不接受以下临时替代作为“Windows TUN 完成”：

- 只添加 route/DNS。
- 只创建 Wintun adapter 但不转发数据。
- 使用系统代理。
- 返回“running”但流量没有从 Wintun 到 CPE 的真实闭环。

## 验收

Windows 真机验收必须包含：

1. 安装后 App 不再显示 `Windows Wintun 数据面待接入`。
2. 开启后能看到 `SD-WAN Verge` Wintun adapter。
3. `route print -4` 显示两个 `/1` 指向 Wintun。
4. `tcpdump/Wireshark` 或 WinDivert 日志显示公网包从物理网卡发往 CPE。
5. `curl ifconfig.me` 的出口与 CPE 路径一致。
6. 断开 CPE 后 3 次失败自动回退，本机直连恢复。
