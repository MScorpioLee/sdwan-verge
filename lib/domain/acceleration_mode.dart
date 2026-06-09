enum AccelerationMode {
  openVpn('openvpn'),
  halfRoute('halfRoute'),
  legacyTun('legacyTun');

  const AccelerationMode(this.json);

  final String json;

  static AccelerationMode fromJson(Object? value) {
    final text = value?.toString().trim();
    return switch (text) {
      'openvpn' || 'openVpn' || 'open_vpn' => AccelerationMode.openVpn,
      'halfRoute' || 'half-route' || 'route' => AccelerationMode.halfRoute,
      'legacyTun' || 'tun' || 'wintun' => AccelerationMode.legacyTun,
      _ => AccelerationMode.halfRoute,
    };
  }
}
