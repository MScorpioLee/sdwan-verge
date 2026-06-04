enum TunMode { tun }

enum TunState { stopped, starting, running, stopping, failed, autoRecovered }

enum TunPermission {
  ready,
  needsVpnConsent,
  needsHelperInstall,
  denied,
  unsupported,
}

const _unset = Object();

class CpeHealth {
  const CpeHealth({
    required this.host,
    required this.reachable,
    this.serviceReady = false,
    this.lastCheckAt,
    this.error,
  });

  final String host;
  final bool reachable;
  final bool serviceReady;
  final DateTime? lastCheckAt;
  final String? error;

  CpeHealth copyWith({
    String? host,
    bool? reachable,
    bool? serviceReady,
    DateTime? lastCheckAt,
    Object? error = _unset,
  }) {
    return CpeHealth(
      host: host ?? this.host,
      reachable: reachable ?? this.reachable,
      serviceReady: serviceReady ?? this.serviceReady,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      error: error == _unset ? this.error : error as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CpeHealth &&
            other.host == host &&
            other.reachable == reachable &&
            other.serviceReady == serviceReady &&
            other.lastCheckAt == lastCheckAt &&
            other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(host, reachable, serviceReady, lastCheckAt, error);
}

class TunStatus {
  const TunStatus({
    required this.mode,
    required this.state,
    required this.permission,
    required this.cpe,
    this.lastError,
  });

  factory TunStatus.defaults({String cpeHost = '192.168.1.140'}) {
    return TunStatus(
      mode: TunMode.tun,
      state: TunState.stopped,
      permission: TunPermission.needsVpnConsent,
      cpe: CpeHealth(host: cpeHost, reachable: false),
    );
  }

  final TunMode mode;
  final TunState state;
  final TunPermission permission;
  final CpeHealth cpe;
  final String? lastError;

  TunStatus copyWith({
    TunMode? mode,
    TunState? state,
    TunPermission? permission,
    CpeHealth? cpe,
    Object? lastError = _unset,
  }) {
    return TunStatus(
      mode: mode ?? this.mode,
      state: state ?? this.state,
      permission: permission ?? this.permission,
      cpe: cpe ?? this.cpe,
      lastError: lastError == _unset ? this.lastError : lastError as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TunStatus &&
            other.mode == mode &&
            other.state == state &&
            other.permission == permission &&
            other.cpe == cpe &&
            other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(mode, state, permission, cpe, lastError);
}
