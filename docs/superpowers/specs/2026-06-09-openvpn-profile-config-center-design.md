# SD-WAN Verge 配置中心与 OpenVPN UDP 优先设计

日期：2026-06-09

## 背景

现有 SD-WAN Verge 已经验证过多条数据面路线：

- macOS/Windows TUN 直连 CPE：可做透明接管，但本地 NAT、回程捕获、RST、防回环和多连接稳定性复杂。
- Half Route：把系统 IPv4 半路由交给 CPE，源 IP 不变，桌面端更稳定，但会改系统路由。
- OpenWrt/iStoreOS 插件：在路由器端应用 CPE 旁路由策略，适合整网生效。

用户确认 CPE 支持 OpenVPN Server，并提供了需要账号密码的 `.ovpn` 配置。该配置当前是 TCP，可在 CPE 服务端同步改为 UDP。OpenVPN 提供标准隧道、重连、认证、MTU/MSS 处理和跨平台客户端能力，比自研 TUN 数据面更适合作为稳定主线。

新的产品方向是：像 Clash 一样提供配置中心，支持多配置、导入、导出、编辑、订阅更新和一键切换；OpenVPN UDP 作为首选模式，Half Route 和 Legacy TUN 作为可选模式保留。

## 设计目标

1. 支持多个加速配置 Profile，每个 Profile 独立保存模式、服务器、协议、端口、DNS、IPv4-only、测速目标等参数。
2. 支持导入 `.ovpn`，解析出 OpenVPN 服务端、协议、端口、证书块、是否需要账号密码等信息。
3. 支持导出 Profile 或 `.ovpn`，默认不导出密码。
4. 支持订阅 URL，像 Clash 订阅一样更新一组 Profile。
5. 默认使用 OpenVPN UDP IPv4，稳定连接到 CPE OpenVPN Server，再由 CPE 负责分流和出口。
6. 保留 Half Route 和 Legacy TUN 的入口，便于对比和回退，但默认推荐 OpenVPN。
7. 密码、token、私钥等敏感信息不进入普通配置 JSON、不进日志、不提交到仓库。
8. 保留现有 Clash 风格 UI、仪表盘、连接、测速、日志和设置页面风格。

## 非目标

本阶段不实现：

- Clash/Mihomo 规则引擎或代理节点兼容。
- CPE 私有协议。
- 服务端 OpenVPN 配置下发；CPE 服务端仍由用户在 CPE 后台配置。
- iOS/Android 内置 OpenVPN 全功能客户端。移动端只保留后续立项入口。
- 自动破解或读取用户密码。
- 将真实 `.ovpn`、证书私钥或账号密码提交进仓库。

## 产品模型

### Profile

Profile 是用户真正切换的加速配置。一个 Profile 可以来自本地创建、`.ovpn` 导入或订阅。

核心字段：

```json
{
  "id": "profile-uuid",
  "name": "公司 CPE UDP",
  "mode": "openvpn",
  "enabled": true,
  "source": "local",
  "cpeIp": "192.168.1.140",
  "dnsMode": "cpe",
  "ipv4Only": true,
  "retainTrafficHistory": false,
  "latencyTargets": ["google", "youtube", "github", "claude", "amazon"]
}
```

### OpenVPN 配置

OpenVPN Profile 增加：

```json
{
  "openvpn": {
    "remoteHost": "192.168.1.140",
    "remotePort": 10189,
    "protocol": "udp4",
    "authUserPass": true,
    "credentialRef": "keychain-or-credential-manager-id",
    "configRef": "stored-redacted-ovpn-profile-id",
    "redirectGateway": "def1",
    "tunName": "auto",
    "mtu": "auto",
    "mssfix": "auto",
    "pullFilterIpv6": true
  }
}
```

配置中心允许用户把当前 TCP 配置改成 UDP，但 UI 必须提示：CPE OpenVPN Server 的协议也必须同步改为 UDP，否则客户端无法连接。

推荐 OpenVPN 片段：

```ovpn
proto udp4
remote 192.168.1.140 10189
redirect-gateway def1
auth-user-pass
pull-filter ignore "ifconfig-ipv6"
pull-filter ignore "route-ipv6"
```

### Half Route 配置

Half Route Profile 保留：

```json
{
  "halfRoute": {
    "gateway": "192.168.1.140",
    "syncDnsWithAcceleration": true,
    "dnsServers": ["192.168.1.140"],
    "ipv4Only": true,
    "autoRollback": true
  }
}
```

Half Route 不接管局域网内通信，只处理 IPv4 外网半路由。DNS 是否跟随 CPE 由 Profile 决定。

### Legacy TUN 配置

Legacy TUN 保留为实验模式：

```json
{
  "legacyTun": {
    "cpeGateway": "192.168.1.140",
    "ipv4Only": true,
    "natTtlSeconds": 600,
    "connectionLimit": 300,
    "eventLogLimit": 1000
  }
}
```

UI 中标注为实验模式，不作为默认推荐。

## 订阅模型

订阅用于批量同步 Profile。第一阶段使用 SD-WAN Verge 自有 JSON/YAML 格式，不直接兼容 Clash 订阅，因为 Clash 节点和 OpenVPN/CPE 隧道不是同一种配置。

订阅字段：

```json
{
  "id": "subscription-uuid",
  "name": "公司配置订阅",
  "url": "https://example.com/sdwan-profiles.json",
  "enabled": true,
  "updateIntervalHours": 24,
  "lastUpdatedAt": "2026-06-09T10:00:00+08:00",
  "lastError": null
}
```

订阅更新规则：

- 订阅 Profile 使用稳定 `remoteId` 匹配更新。
- 本地编辑项默认覆盖订阅项，避免用户改名、改 DNS 后被刷新覆盖。
- 删除订阅不会立即删除已导入的本地副本，需用户确认。
- 订阅内容不得包含明文密码；只能声明 `authUserPass: true`。

## 导入与导出

### `.ovpn` 导入

导入流程：

1. 用户选择 `.ovpn`。
2. App 解析 `proto`、`remote`、`redirect-gateway`、`auth-user-pass`、`dhcp-option DNS`、IPv6 route/push 相关项。
3. UI 展示可编辑摘要：名称、协议、地址、端口、是否需要账号密码、IPv4-only。
4. 用户保存后生成 Profile。
5. 如果需要账号密码，提示用户输入并保存到系统安全存储。

导入时保存原始 OpenVPN 配置的规范化副本，但敏感块按类型保护：

- `<ca>` 可保存到本地 profile store。
- `<cert>`、`<key>` 若出现，标记为敏感，使用权限更严格的本地文件或系统安全存储。
- `auth-user-pass` 不写明文路径；运行时生成临时 auth 文件。

### 导出

导出类型：

- SD-WAN Verge Profile 包：包含模式、服务器、端口、DNS、测速目标等，不含密码。
- 单个 `.ovpn`：适合给 OpenVPN 官方客户端导入，默认不含密码。
- 诊断包：只包含状态、日志摘要和脱敏配置，不含证书私钥、密码、token。

导出前 UI 明确提示是否包含敏感证书块。默认不导出密码。

## 账号密码与安全

OpenVPN 账号密码按平台存储：

- macOS：Keychain。
- Windows：Credential Manager。
- Linux：Secret Service；不可用时提示仅本次会话输入。

运行时：

1. helper 从安全存储读取账号密码。
2. 在临时目录生成权限受限的 auth 文件。
3. 启动 OpenVPN 时传 `--auth-user-pass <temp-file>`。
4. 进程结束、失败、回退或 App 退出时删除临时 auth 文件。
5. 日志中永不打印用户名、密码、auth 文件内容。

## 平台数据面

### macOS

OpenVPN 模式：

- helper 负责启动和停止 OpenVPN 进程。
- 优先使用随 App 打包的 OpenVPN 二进制；如果未打包，则检测系统 `openvpn` 并给出安装提示。
- 菜单栏和关闭窗口行为保持：关闭窗口最小化到菜单栏，退出前自动停止加速。

Half Route 模式：

- 保留当前 macOS half route helper。
- 只用于用户显式选择 Half Route。

Legacy TUN：

- 保留旧实现做对比，不再默认打开。

### Windows

OpenVPN 模式：

- helper service 管理 OpenVPN 进程。
- 首次安装 service 需要管理员权限，日常开关不重复弹权限。
- 使用 Credential Manager 保存密码。

Half Route 模式：

- 保留现有 Windows helper service 的 route/DNS 能力。

Legacy TUN：

- 保留 Wintun 旧方案入口，标记实验。

### Linux

OpenVPN 模式：

- 使用 systemd/polkit helper 管理 OpenVPN。
- Secret Service 不可用时允许仅本次输入账号密码。

Half Route 模式：

- 保留 `/proc/net/dev`、`ip route` 和 DNS 处理逻辑。

### OpenWrt/iStoreOS

路由器插件仍以 Half Route 为推荐，因为安装在路由器上时能直接影响 LAN 客户端。

插件增加可配置项：

- 模式：Half Route / TUN 实验。
- CPE 网关。
- DNS 同步。
- 常用网站连接测试目标。
- 流量统计开关。

OpenVPN Server 位于 CPE，不在此插件内自动管理。

## UI 调整

### 新增“配置”页

类似 Clash 配置页：

- 配置卡片列表。
- 当前使用标记。
- 导入 `.ovpn`。
- 添加本地配置。
- 添加订阅。
- 更新订阅。
- 编辑、复制、导出、删除。

### 设置页调整

全局设置保留：

- 开机启动。
- 关闭窗口最小化。
- 退出时停止加速。
- 保留历史流量统计默认值。

与连接相关的 CPE、DNS、协议、端口、MTU、测速目标迁移到 Profile 编辑页。

### 首页调整

首页显示当前 Profile：

- 名称。
- 模式。
- 远端地址与协议。
- 账号状态。
- 连接状态。
- 当前出口和速率。

开启按钮使用当前 Profile。

## 状态与日志

统一状态字段：

```json
{
  "mode": "openvpn",
  "profileId": "profile-uuid",
  "profileName": "公司 CPE UDP",
  "state": "running",
  "permission": "ready",
  "adapterName": "OpenVPN",
  "remote": "192.168.1.140:10189/udp4",
  "ipv4Only": true,
  "txBytes": 0,
  "rxBytes": 0,
  "txRate": 0,
  "rxRate": 0,
  "lastError": null
}
```

日志事件：

- Profile 导入、导出、切换。
- 订阅更新成功或失败。
- OpenVPN 启动、认证失败、连接成功、重连、停止。
- CPE 不可达和自动回退。
- DNS 应用或恢复。

日志默认保留最近 1000 条或 512 KB，避免运行久后无限增长。

## 健康检测与测速

Profile 可配置测速目标。默认目标：

- Cloudflare
- Google
- YouTube
- GitHub
- Claude
- Amazon

OpenVPN 模式检测：

- L1：OpenVPN 进程状态。
- L2：隧道 IP 与路由是否存在。
- L3：通过隧道访问固定探测 URL。

Half Route 模式检测：

- L1：CPE ping/TCP。
- L3：外网探测。

局域网内地址不参与“加速成功”检测，避免把 LAN 通信误判为外网加速。

## 迁移策略

旧配置迁移：

- 现有 `SdwanProfile` 自动迁移为一个 Half Route Profile。
- `syncDnsWithAcceleration` 转入该 Profile。
- `retainTrafficHistory` 保持为全局默认。
- `TunMode.tun` 更名或包装为 `AccelerationMode.legacyTun`，旧状态解析保持兼容。

默认新安装：

- 如果没有配置，创建一个默认 OpenVPN Profile 草稿，提示导入 `.ovpn`。
- 若用户只输入 CPE 网关，则创建 Half Route Profile。

## 测试计划

单元测试：

- Profile JSON 兼容迁移。
- `.ovpn` 解析：TCP、UDP、auth-user-pass、redirect-gateway、IPv6 pull-filter。
- 订阅合并和本地覆盖。
- 密码字段不进入普通配置 JSON。
- 导出默认不包含密码。

平台测试：

- macOS/Windows/Linux helper 参数生成。
- OpenVPN 缺失时错误提示。
- auth 临时文件创建与清理。
- stop/退出时停止 OpenVPN 或 Half Route。

非破坏性验证：

- 不在开发机直接接管网络。
- 可运行 `flutter analyze` 和 `flutter test`。
- OpenVPN 真机连接由用户在独立环境验证。

## 交付顺序

1. 配置模型和迁移。
2. `.ovpn` 解析、导入、编辑、导出。
3. 配置页 UI。
4. OpenVPN helper 启停骨架和安全凭据。
5. macOS/Windows OpenVPN 真实启动。
6. Linux OpenVPN 启动。
7. 订阅 URL 更新。
8. OpenWrt/iStoreOS 插件配置项补齐。

第一轮实施只做桌面端配置中心与 OpenVPN UDP MVP，不触发 GitHub Action 打包，等用户通知后再出包。
