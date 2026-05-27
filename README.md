# SD-WAN Client

Flutter multi-platform client for the SD-WAN acceleration workflow currently represented by the BAT script in this directory.

## First Release Scope

- Windows desktop is the primary supported platform.
- Windows can add and remove the acceleration routes from the original BAT script.
- Windows can set or restore DNS on the active network interface.
- macOS, Web, iOS, Android, and Linux launch with platform capability messaging.

## Default Configuration

- Company: 宁波市富金园艺灌溉设备有限公司
- CPE gateway: `192.168.1.140`
- Primary DNS: `223.5.5.5`
- Secondary DNS: `114.114.114.114`

## Development

```bash
flutter pub get
flutter test
flutter analyze
flutter build macos --debug
```

Run Windows manual acceptance on a Windows machine:

```text
docs/windows-manual-acceptance.md
```
