# SD-WAN Verge TUN 优先架构设计

日期：2026-06-03

## 背景

当前项目已经有三个方向：

- Windows BAT 等价路线：添加两条 `/1` 路由到 CPE `192.168.1.140`，并设置或恢复 DNS。
- OpenWrt/iStoreOS 插件路线：在路由器端下发到旁路由 CPE 的策略，整网生效。
- Flutter 多端管理器路线：前台展示状态、配置、日志，并调用平台能力层。

用户进一步确认：

- 不希望优先做系统代理。
- 不希望直接修改本地物理网卡的 IP、默认网关和 DNS。
- CPE 类似旁路由，可以作为 SD-WAN 出口或下一跳。
- 下一阶段先做 TUN 虚拟网卡模式。

因此本设计把 TUN/VPN 模式改为默认主线，route/DNS 命令模式降级为兼容 fallback，系统代理模式暂不实现。

## 设计目标

1. 默认用 TUN 虚拟网卡接管流量，不直接修改物理网卡配置。
2. 用后台 `sdwan-core` 负责 TUN 生命周期、CPE 健康检测、转发策略和自动回退。
3. Flutter 前台只做管理器：开启/关闭、状态、日志、配置和错误提示。
4. CPE 异常时自动停止 TUN，恢复系统原网络路径，避免整机断网。
5. 第一阶段优先做 macOS TUN MVP，验证真实环境可行后再做 Windows、Linux、Android、iOS。
6. OpenWrt/iStoreOS 插件继续作为整网模式保留。

## 非目标

本阶段不实现：

- Clash/mihomo 订阅、节点选择和规则分流。
- 系统 HTTP/SOCKS 代理模式。
- 自建公网 VPN 服务端。
- iOS/Android 上架或商店合规材料。
- 复杂应用级分流。
- CPE 固件改造。

## 产品模式

`SD-WAN Verge` 的网络模式调整为：

```text
默认模式：TUN 旁路由模式
  - 创建虚拟网卡
  - 接管目标流量
  - 交给 sdwan-core
  - sdwan-core 转发到 CPE
  - CPE 异常时自动停止 TUN

备用模式：路由命令模式
  - 保留现有 BAT 等价能力
  - 适合应急或不支持 TUN 的桌面环境

整网模式：OpenWrt/iStoreOS 插件
  - 路由器端统一下发旁路由策略
  - 手机和电脑都可通过路由器受益
```

系统代理模式暂不进入第一阶段 UI。

## 核心架构

```text
Flutter Manager
  - 模式选择
  - 开启/关闭
  - CPE 状态
  - TUN 状态
  - 日志和错误展示
        ↓ 本地 API
sdwan-core
  - TUN 生命周期
  - CPE 健康检测
  - 转发策略
  - 自动回退
  - 日志流
        ↓
Platform TUN Adapter
  - macOS Network Extension / utun
  - Windows Wintun / service
  - Linux /dev/net/tun / helper
  - Android VpnService
  - iOS NEPacketTunnelProvider
        ↓
CPE 192.168.1.140
```

## macOS 第一阶段 MVP

macOS 第一阶段采用 `Network Extension` 的 Packet Tunnel 方向。

模块边界：

- Flutter App
  - 负责 UI、配置和调用本地 Core API。
  - 不直接创建 TUN。

- Packet Tunnel Provider
  - 系统 VPN 扩展。
  - 创建虚拟网络接口。
  - 读取 TUN 包并交给本地 Core 或扩展内 Core。

- sdwan-core
  - 负责 CPE 健康检测。
  - 维护运行状态。
  - 决定是否保持 TUN。
  - 记录日志。

第一阶段不追求完整全协议转发，先验证最小闭环：

1. App 可以安装或启用 Packet Tunnel 配置。
2. 用户首次允许 VPN/TUN 配置。
3. App 可以启动和停止 TUN。
4. Core 可以检测 CPE `192.168.1.140` 是否在线。
5. CPE 连续失败时自动停止 TUN，并在 UI 显示“CPE 异常，已恢复直连”。
6. 日志能记录启动、停止、健康检测、失败原因。

## 转发策略

TUN 模式必须解决“抓到包之后如何交给 CPE”的问题。

第一阶段采用保守策略：

- 默认只验证 TUN 生命周期和 CPE 健康检测。
- 不把所有流量强制黑盒转发，避免在转发语义不明时制造断网风险。
- 在确认 CPE 支持的转发方式后，再实现数据转发。

CPE 转发方式按优先级确认：

1. 标准代理入口
   - SOCKS5 或 HTTP CONNECT。
   - 如果存在，TUN Core 可以把 TCP 流转换到代理入口。

2. 旁路由下一跳
   - CPE 可以作为 LAN 下一跳转发 IP 包。
   - Core 需要通过平台能力把 TUN 包注入到正常网络栈或原始 socket 转发。

3. 私有协议入口
   - CPE 提供自定义 TCP/UDP 控制和数据通道。
   - Core 需要实现协议适配。

若 CPE 的转发入口未确认，MVP 只做 TUN 生命周期和自动回退，不声称已完成加速转发。

## CPE 健康检测

健康检测分三层：

```text
L1：CPE 可达
  - ping 192.168.1.140 或 TCP 端口探测

L2：CPE 服务可用
  - 检测代理端口、健康接口或私有协议握手

L3：出口可用
  - 通过 CPE 路径测试外网 IP 或指定业务地址
```

自动回退规则：

- 开启前 L1 必须通过。
- 若配置了 CPE 服务端口，开启前 L2 必须通过。
- 运行中连续 3 次失败，停止 TUN。
- 停止 TUN 后不修改物理网卡配置。
- UI 保留失败日志和最后一次错误。

## 跨平台路线

### macOS

- 第一优先级。
- 使用 Network Extension / Packet Tunnel Provider。
- 首次需要用户允许 VPN 配置。
- 后续由 App 控制开关。

### Windows

- 使用 Wintun 或等价 Layer 3 TUN 驱动。
- 配合后台 service。
- 安装驱动或 service 时需要管理员授权一次。
- 后续由 Flutter Manager 调用 service。

### Linux

- 使用 `/dev/net/tun`。
- 配合 systemd service 或 polkit helper。
- 安装 helper 后由用户态管理。

### Android

- 使用 `VpnService`。
- 用户授权 VPN 连接。
- App 内启动或停止。
- Google Play 上架时需要 VPN 用途说明。

### iOS

- 使用 `NEPacketTunnelProvider`。
- 需要 Network Extension 能力、App Group 和 VPN 配置。
- 用户首次允许 VPN 配置。

## Core API 调整

新增 TUN 相关 API：

- `core.tun.status()`
  - 返回 TUN 状态、CPE 健康、平台权限、最后错误。
- `core.tun.start(profileId)`
  - 启动 TUN。
- `core.tun.stop()`
  - 停止 TUN。
- `core.tun.healthCheck()`
  - 主动执行 CPE 健康检测。
- `core.tun.logs(since)`
  - 查询 TUN 日志。

状态模型：

```json
{
  "mode": "tun",
  "tunState": "stopped",
  "platform": "macOS",
  "permission": "needsVpnConsent",
  "cpe": {
    "host": "192.168.1.140",
    "reachable": false,
    "serviceReady": false,
    "lastCheckAt": null
  },
  "fallback": {
    "routeModeAvailable": true,
    "routerPluginAvailable": false
  },
  "lastError": null
}
```

`tunState` 可取值：

- `stopped`
- `starting`
- `running`
- `stopping`
- `failed`
- `autoRecovered`

`permission` 可取值：

- `ready`
- `needsVpnConsent`
- `needsHelperInstall`
- `denied`
- `unsupported`

## UI 调整

首页主按钮改为：

- 开启 TUN
- 关闭 TUN

首页状态卡：

- TUN 状态
- CPE 状态
- 当前模式
- 自动回退状态

设置页：

- 默认模式：TUN
- 备用模式：路由命令
- CPE 地址：`192.168.1.140`
- CPE 健康检测方式：ping/TCP/HTTP health
- 连续失败次数：默认 3

帮助页：

- 解释 TUN 不修改物理网卡。
- 解释首次 VPN/TUN 授权。
- 解释 CPE 异常自动回退。

## 风险和约束

- TUN 只是虚拟网卡入口，仍需要确认 CPE 的真实转发入口。
- macOS/iOS Network Extension 需要 Xcode target、entitlement 和配置流程。
- Windows Wintun/service 需要安装和卸载流程。
- Android 使用 `VpnService` 后，商店分发需要说明 VPN 用途。
- 如果 CPE 只支持旁路由下一跳，不支持标准代理或隧道，TUN 数据转发实现会比 route fallback 更复杂。
- MVP 必须避免“开启后假装加速，实际黑洞流量”。

## 验收标准

macOS TUN MVP 完成时：

- App 显示默认模式为 TUN。
- App 能提示并引导首次 VPN/TUN 授权。
- App 能启动和停止 TUN 配置。
- App 能检测 CPE `192.168.1.140` 可达性。
- CPE 连续失败后自动停止 TUN。
- 不修改物理网卡 IP、默认网关和 DNS。
- 日志显示启动、停止、健康检测和自动回退原因。
- route fallback 仍可作为兼容模式保留，但不作为默认主按钮。

跨平台后续完成时：

- Windows 通过 service + TUN 驱动实现同等开关体验。
- Linux 通过 helper + `/dev/net/tun` 实现同等开关体验。
- Android 通过 `VpnService` 实现手机端 TUN。
- iOS 通过 `NEPacketTunnelProvider` 实现手机端 TUN。
