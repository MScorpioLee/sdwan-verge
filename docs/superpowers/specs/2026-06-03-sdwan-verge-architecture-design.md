# SD-WAN Verge 架构设计

日期：2026-06-03

## 背景

当前 Flutter 项目已经从 BAT 脚本迁移出第一版桌面客户端：

- Flutter 前台界面包含仪表盘、设置、日志、帮助。
- `SdwanController` 负责加载配置、刷新状态和执行操作。
- `NetworkPlatformGateway` 抽象平台能力。
- Windows 已有 `WindowsNetworkGateway`，封装 `route`、`netsh`、`ipconfig` 和 UAC 重启。
- macOS、Web、Linux、iOS、Android 当前走 `UnsupportedNetworkGateway`，只展示受限提示。

用户确认下一阶段采用“类似 Clash Verge 的形式”，并选择方案 B：**前台 Flutter 管理器 + 后台 Core/Helper 架构**。本设计不要求第一步集成 mihomo/Clash 内核，也不做订阅、节点、规则分流和 TUN 模式；目标是先把 SD-WAN 路由/DNS 管理做成稳定的前后台结构。

随后用户提出是否可以做 OpenWrt 或 iStoreOS 插件。该路线可行，并且适合做成路由器端能力：如果 OpenWrt/iStoreOS 路由器本身控制 SD-WAN 加速路由和 DNS，整网设备可以统一生效，不需要每台电脑都安装桌面客户端。

## 设计目标

1. 把产品形态从“一个按钮式工具”升级为“SD-WAN Verge 管理器”。
2. 明确分离 Flutter 前台界面和 Core 能力层。
3. 为后续独立 helper 进程、Windows Service、macOS LaunchDaemon 或 privileged helper 留出接口。
4. 让 macOS 不再只是“平台不支持”，而是进入可实现路线：先通过授权命令执行路由/DNS，后续安装后台 helper。
5. 保留现有 Windows 路由/DNS 功能和测试，不破坏第一版已完成能力。
6. 为 OpenWrt/iStoreOS 插件预留协议和配置模型，使桌面端后续可以管理路由器端 Core。

## 非目标

本阶段不实现以下内容：

- 不集成 mihomo/Clash 内核。
- 不实现订阅、节点选择、规则分流、TUN 模式。
- 不实现账号系统、远程下发配置、集中管理后台。
- 不立即安装 Windows Service 或 macOS privileged helper。
- 不立即实现 OpenWrt/iStoreOS 插件打包和 iStore 上架。
- 不在移动端直接修改系统路由或 DNS。

## 产品形态

产品命名建议为 `SD-WAN Verge`。

前台 UI 采用 Verge 类工具的组织方式：

- 首页：总开关、Core 状态、当前平台能力、当前配置档、路由/DNS 状态。
- 配置档：默认公司配置，后续支持多配置档切换。
- 路由：展示加速路由策略和当前系统路由匹配状态。
- DNS：展示 DNS 模式、当前网卡、主备 DNS 和同步策略。
- 日志：展示 Core 日志、系统命令日志、错误详情和复制按钮。
- 设置：开机启动、托盘驻留、Core 模式、权限模式、默认配置。
- 关于/帮助：解释 Windows/macOS 权限要求和验收步骤。

托盘菜单作为桌面端目标能力：

- 开启加速。
- 关闭加速。
- 打开面板。
- 刷新状态。
- 退出。

## 架构总览

采用三层结构：

```text
Flutter Manager
  - UI
  - 配置编辑
  - 托盘/开机启动入口
  - 日志展示
        ↓
Core Service API
  - 状态查询
  - 开启/关闭加速
  - DNS 设置/恢复
  - 日志流
  - 权限状态
        ↓
Platform Gateway
  - Windows route/netsh/ipconfig/UAC
  - macOS route/networksetup/cache flush
  - OpenWrt ip route/uci/dnsmasq/init.d
  - Unsupported gateway for Web/Linux/mobile
```

第一阶段 Core 可以内嵌在 Flutter 进程内，使用 Dart 类调用。接口必须按“可远程调用”的形式设计，后续可以无痛迁移为本地 HTTP、Unix domain socket、named pipe 或 JSON-RPC。

第二阶段 Core 拆成独立 `sdwan-core` helper 进程。Flutter 通过本地 API 调用 helper。

第三阶段 helper 升级为系统级后台：

- Windows：Windows Service 或启动时提权 helper。
- macOS：LaunchDaemon 或 SMAppService/privileged helper。

第四阶段增加路由器端插件：

- OpenWrt：LuCI 插件 + `/etc/init.d/sdwan-verge` 服务 + UCI 配置。
- iStoreOS：基于 OpenWrt 包结构做 iStore 可安装插件。

## Core API 设计

Core 以命令式 API 对外暴露：

- `core.status()`
  - 返回 Core 运行状态、平台、权限、活动配置、路由状态、DNS 状态。
- `core.start(profileId)`
  - 开启加速。
- `core.stop(profileId)`
  - 关闭加速。
- `core.setDns(profileId)`
  - 对活动网卡设置配置档 DNS。
- `core.restoreDns()`
  - 恢复活动网卡 DNS 自动获取。
- `core.reloadConfig()`
  - 重新加载配置。
- `core.logs(since)`
  - 查询日志或订阅日志流。

Core 状态模型：

```json
{
  "coreMode": "embedded",
  "coreState": "running",
  "platform": "macOS",
  "permission": "limited",
  "activeProfileId": "default",
  "acceleration": "disabled",
  "route": {
    "lowerHalfRoute": false,
    "upperHalfRoute": false,
    "gateway": "192.168.1.140"
  },
  "dns": {
    "mode": "unknown",
    "interfaceName": null,
    "servers": []
  }
}
```

`coreMode` 可取值：

- `embedded`：Core 内嵌在 Flutter 进程。
- `sidecar`：Core 独立 helper 进程。
- `systemService`：Core 以系统服务方式运行。

`coreState` 可取值：

- `running`
- `notRunning`
- `starting`
- `stopping`
- `error`

`permission` 可取值：

- `ready`
- `limited`
- `needsElevation`
- `denied`

## 代码边界

现有代码演进为以下模块：

- `lib/core/core_service.dart`
  - 定义 `CoreService` 接口。
  - 暴露 status/start/stop/setDns/restoreDns/logs。

- `lib/core/embedded_core_service.dart`
  - 第一阶段实现。
  - 内部复用当前 `NetworkPlatformGateway`。

- `lib/core/core_models.dart`
  - `CoreStatus`、`CoreMode`、`CoreState`、`PermissionState`、`CoreLogEvent`。

- `lib/services/sdwan_controller.dart`
  - 从直接依赖 `NetworkPlatformGateway` 改为依赖 `CoreService`。
  - 仍负责通知 UI 和保存配置。

- `lib/platform/macos/macos_network_gateway.dart`
  - 后续实现 macOS 路由和 DNS。

- `lib/platform/windows/windows_network_gateway.dart`
  - 保留当前 Windows 实现。
  - 后续可被 sidecar/helper 复用。

- `lib/ui/`
  - UI 文案和布局升级为 `SD-WAN Verge` 风格。

- `router/openwrt/`
  - 后续新增 OpenWrt/iStoreOS 插件源码和打包文件。

## OpenWrt/iStoreOS 插件路线

OpenWrt/iStoreOS 插件建议作为独立交付物，和桌面端共享 Core API 语义，但不共享 Flutter UI。

插件形态：

```text
luci-app-sdwan-verge
  - LuCI Web 页面
  - 配置 CPE 网关、DNS、启用开关
  - 查看状态和日志

sdwan-verge-core
  - shell 或轻量二进制 Core
  - 执行 ip route / uci / dnsmasq
  - 提供本地 HTTP/ubus 接口

/etc/config/sdwan_verge
  - UCI 配置文件

/etc/init.d/sdwan-verge
  - 启动、停止、重载、开机启动
```

路由器端开启加速的典型动作：

```sh
ip route add 0.0.0.0/1 via 192.168.1.140
ip route add 128.0.0.0/1 via 192.168.1.140
/etc/init.d/dnsmasq restart
```

路由器端关闭加速的典型动作：

```sh
ip route del 0.0.0.0/1
ip route del 128.0.0.0/1
/etc/init.d/dnsmasq restart
```

DNS 可以通过 UCI 管理 dnsmasq 或 WAN DNS：

```sh
uci set dhcp.@dnsmasq[0].server='223.5.5.5'
uci add_list dhcp.@dnsmasq[0].server='114.114.114.114'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

实际实现时必须先确认目标路由器的网络拓扑：

- OpenWrt/iStoreOS 是否是 LAN 默认网关。
- CPE `192.168.1.140` 是否和路由器在同一网段。
- 加速路由应作用于路由器自身、LAN 客户端，还是指定源 IP/MAC。
- DNS 是只改路由器自身解析，还是下发给 LAN 客户端。
- 防火墙使用 nftables、iptables 还是 fw4 默认规则。

桌面端与路由器插件的协作方式：

```text
Flutter Manager
  ↓ HTTP/ubus API
OpenWrt/iStoreOS sdwan-verge-core
  ↓
ip route / uci / dnsmasq / firewall
```

桌面端可以作为远程管理器：

- 扫描或手动添加路由器地址。
- 输入路由器管理 token。
- 查看路由器端 Core 状态。
- 开启/关闭路由器端加速。
- 同步配置档到路由器。

路由器插件相对桌面本地 Core 的优势：

- 整个局域网统一生效。
- 不需要每台电脑单独设置路由和 DNS。
- 开机后可由 init.d 自动恢复规则。
- 更接近企业或门店部署方式。

限制：

- 如果 OpenWrt/iStoreOS 不是默认网关，插件只能影响经过它的流量。
- 错误路由可能影响整网访问，必须有回滚和安全超时。
- iStoreOS 上架需要符合插件包结构、图标、依赖和安装脚本要求。

## macOS 能力路线

macOS 支持修改系统路由和 DNS，但需要权限。

第一阶段可以用授权命令执行：

```bash
osascript -e 'do shell script "route -n add -net 0.0.0.0 -netmask 128.0.0.0 192.168.1.140" with administrator privileges'
osascript -e 'do shell script "route -n add -net 128.0.0.0 -netmask 128.0.0.0 192.168.1.140" with administrator privileges'
networksetup -setdnsservers "<SERVICE_NAME>" 223.5.5.5 114.114.114.114
dscacheutil -flushcache
killall -HUP mDNSResponder
```

关闭加速：

```bash
osascript -e 'do shell script "route -n delete -net 0.0.0.0 -netmask 128.0.0.0" with administrator privileges'
osascript -e 'do shell script "route -n delete -net 128.0.0.0 -netmask 128.0.0.0" with administrator privileges'
networksetup -setdnsservers "<SERVICE_NAME>" Empty
```

注意：

- macOS `route add` 默认不是持久路由，重启或网络变化后可能丢失。
- 第一阶段在 App 开启加速时重新设置。
- 正式后台阶段由 LaunchDaemon/helper 监听网络变化并恢复路由。

## 权限策略

Windows：

- 当前已有 UAC 重启。
- 后续 helper 模式下，安装时完成一次授权，运行时由 helper 执行系统命令。

macOS：

- 第一阶段使用按操作弹出的管理员授权。
- 第二阶段 sidecar 仍可按需弹授权。
- 第三阶段用 LaunchDaemon 或 privileged helper 减少反复输入密码。

Web/mobile：

- 只提供配置查看、说明和下载入口。
- 不直接修改系统网络。

## UI 调整

第一阶段 UI 调整不做大规模视觉重写，只做结构和文案升级：

- 应用标题改为 `SD-WAN Verge`。
- 首页增加 Core 状态卡。
- 首页保留加速状态、活动网卡、DNS 状态。
- 设置页增加 Core 模式显示：内嵌 Core、后续 helper、后续系统服务。
- 帮助页增加“为什么像 Clash Verge 分前台和后台”的说明。
- 日志页区分 UI 日志、Core 日志、系统命令日志。

后续视觉增强：

- 左侧导航更接近 Verge 类工具：概览、配置、路由、DNS、日志、设置、关于。
- 托盘菜单使用桌面插件实现。
- 状态色保持克制，避免把网络工具做成营销页。

## 数据迁移

现有配置结构可以保留：

- `AppConfig`
- `SdwanProfile`
- `activeProfileId`
- `profiles`

新增 Core 设置：

```json
{
  "core": {
    "mode": "embedded",
    "autoStart": false,
    "trayEnabled": true,
    "launchAtLogin": false
  }
}
```

第一阶段可先在模型里预留字段，不必立即实现开机启动和托盘。

## 测试计划

自动化测试：

- `CoreStatus` 序列化和默认值。
- `EmbeddedCoreService` 调用平台网关的顺序。
- `SdwanController` 从依赖 gateway 迁移为依赖 CoreService 后，现有控制器测试继续通过。
- UI 显示 Core 状态、平台权限和原有加速/DNS 状态。
- Unsupported 平台通过 CoreService 返回受限状态，而不是 UI 自己判断。

手工验证：

- macOS build 能打开 `SD-WAN Verge`。
- Web build 能显示受限平台提示。
- Windows 现有 route/netsh 行为不回退。
- macOS 路由/DNS实现阶段必须在真实 macOS 上验证 `route -n get`、`netstat -rn`、`networksetup -getdnsservers`。

## 分阶段交付

### Phase 1：内嵌 Core 架构

- 新增 `CoreService`、`EmbeddedCoreService` 和 Core 状态模型。
- `SdwanController` 改为依赖 `CoreService`。
- UI 文案改为 `SD-WAN Verge`。
- 首页显示 Core 状态。
- 保持所有现有测试通过。

### Phase 2：macOS 平台网关

- 新增 `MacosNetworkGateway`。
- 支持活动网络服务识别。
- 支持 macOS 路由添加/删除。
- 支持 DNS 设置/恢复。
- 支持刷新 DNS 缓存。
- 通过授权命令执行需要管理员权限的操作。

### Phase 3：sidecar helper

- 新增 `sdwan-core` 独立进程。
- Flutter 通过本地 API 调用 Core。
- Core 提供日志流。
- Core 管理平台网关。

### Phase 4：系统级后台

- Windows Service。
- macOS LaunchDaemon 或 privileged helper。
- 开机启动和网络变化后自动恢复路由。
- 托盘常驻和后台状态恢复。

### Phase 5：OpenWrt/iStoreOS 插件

- 新增 `router/openwrt` 插件工程。
- 实现 UCI 配置：CPE、DNS、启用状态、同步 DNS。
- 实现 init.d 服务：start、stop、restart、status。
- 实现 LuCI 页面：总开关、配置、状态、日志。
- 实现安全回滚：开启失败时删除已添加路由，DNS 修改失败时恢复旧配置。
- 提供 IPK 构建说明。
- iStoreOS 适配插件元信息和图标。

## 风险和约束

- macOS 持久路由不是简单 `route add` 就能永久保存，必须接受“重启后重设”或做后台 helper。
- macOS privileged helper 涉及签名、安装、卸载和权限审计，不能草率实现。
- Windows Service 同样需要安装器和卸载流程。
- 托盘和开机启动需要引入桌面插件，必须验证 macOS、Windows、Web 条件导入。
- 如果未来接入 mihomo/Clash 内核，配置模型和 Core API 需要新增代理端口、规则、节点和订阅，不应混进当前 SD-WAN 路由/DNS阶段。
- OpenWrt/iStoreOS 插件会影响整网，必须默认提供“恢复路由和 DNS”的紧急入口。

## 验收标准

Phase 1 完成时：

- App 标题和主要 UI 显示为 `SD-WAN Verge`。
- 首页展示 Core 状态。
- `SdwanController` 不再直接编排 `NetworkPlatformGateway`，而是通过 `CoreService`。
- Windows 行为保持现有测试覆盖。
- Web/macOS 仍能构建和运行，并通过 Core 返回平台受限或权限受限状态。
- `flutter analyze`、`flutter test`、`flutter build macos --debug`、`flutter build web` 通过。

Phase 2 完成时：

- macOS 可以在授权后执行加速路由和 DNS 操作。
- macOS 关闭加速可以删除两条路由并恢复 DNS。
- macOS 操作日志能显示具体命令和错误。
- 明确提示 macOS 路由不是永久持久化，必要时可重新开启。

Phase 5 完成时：

- OpenWrt/iStoreOS 插件可安装。
- LuCI 页面能配置 CPE 和 DNS。
- 开启后 `ip route` 能看到两条加速路由。
- 关闭后两条路由被删除。
- dnsmasq 配置按预期设置或恢复。
- 路由器重启后可按 UCI 启用状态恢复。
- 插件提供紧急关闭命令和恢复说明。
