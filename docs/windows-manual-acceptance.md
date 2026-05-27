# Windows Manual Acceptance

Use this checklist on a Windows machine with Flutter desktop enabled.

## Preconditions

- The machine is connected to the same network as the SD-WAN CPE.
- The CPE gateway IP is known. Default: `192.168.1.140`.
- Flutter can build Windows desktop apps.

## Checks

1. Run the app normally.
   - Expected: Windows UAC appears and asks to relaunch as administrator.

2. Open the app as administrator.
   - Expected: Dashboard shows Windows full capability.

3. Click `开启加速`.
   - Expected: Dashboard changes to enabled, or logs explain why it failed.
   - Verify in an administrator terminal:

   ```bat
   route print -4
   ```

   Expected routes:

   - Destination `0.0.0.0`, netmask `128.0.0.0`, gateway configured CPE.
   - Destination `128.0.0.0`, netmask `128.0.0.0`, gateway configured CPE.

4. Click `关闭加速`.
   - Expected: Dashboard changes to disabled.
   - Verify with `route print -4` that the two acceleration routes are gone.

5. Enable `路由操作同步 DNS`, save, then click `开启加速`.
   - Verify:

   ```bat
   netsh interface ip show dnsservers
   ```

   Expected: active interface shows configured primary and secondary DNS.

6. Click `关闭加速`.
   - Expected: DNS is restored to automatic acquisition.

7. Disconnect network and refresh status.
   - Expected: app shows a Chinese message explaining that no active interface was found.
