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

class TrafficStats {
  const TrafficStats({
    this.txBytes = 0,
    this.rxBytes = 0,
    this.txRate = 0,
    this.rxRate = 0,
  });

  final int txBytes;
  final int rxBytes;
  final int txRate;
  final int rxRate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrafficStats &&
            other.txBytes == txBytes &&
            other.rxBytes == rxBytes &&
            other.txRate == txRate &&
            other.rxRate == rxRate;
  }

  @override
  int get hashCode => Object.hash(txBytes, rxBytes, txRate, rxRate);
}

class TunConnection {
  const TunConnection({
    required this.lastSeen,
    required this.proto,
    required this.source,
    required this.target,
    this.domain,
    required this.via,
    required this.txBytes,
    required this.rxBytes,
    this.txRate = 0,
    this.rxRate = 0,
    this.dnsRedirect = false,
  });

  final String lastSeen;
  final String proto;
  final String source;
  final String target;
  final String? domain;
  final String via;
  final int txBytes;
  final int rxBytes;
  final int txRate;
  final int rxRate;
  final bool dnsRedirect;

  TunConnection copyWith({
    String? lastSeen,
    String? proto,
    String? source,
    String? target,
    Object? domain = _unset,
    String? via,
    int? txBytes,
    int? rxBytes,
    int? txRate,
    int? rxRate,
    bool? dnsRedirect,
  }) {
    return TunConnection(
      lastSeen: lastSeen ?? this.lastSeen,
      proto: proto ?? this.proto,
      source: source ?? this.source,
      target: target ?? this.target,
      domain: domain == _unset ? this.domain : domain as String?,
      via: via ?? this.via,
      txBytes: txBytes ?? this.txBytes,
      rxBytes: rxBytes ?? this.rxBytes,
      txRate: txRate ?? this.txRate,
      rxRate: rxRate ?? this.rxRate,
      dnsRedirect: dnsRedirect ?? this.dnsRedirect,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TunConnection &&
            other.lastSeen == lastSeen &&
            other.proto == proto &&
            other.source == source &&
            other.target == target &&
            other.domain == domain &&
            other.via == via &&
            other.txBytes == txBytes &&
            other.rxBytes == rxBytes &&
            other.txRate == txRate &&
            other.rxRate == rxRate &&
            other.dnsRedirect == dnsRedirect;
  }

  @override
  int get hashCode => Object.hash(
    lastSeen,
    proto,
    source,
    target,
    domain,
    via,
    txBytes,
    rxBytes,
    txRate,
    rxRate,
    dnsRedirect,
  );
}

class TrafficSample {
  const TrafficSample({
    required this.at,
    required this.txRate,
    required this.rxRate,
  });

  final DateTime at;
  final int txRate;
  final int rxRate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TrafficSample &&
            other.at == at &&
            other.txRate == txRate &&
            other.rxRate == rxRate;
  }

  @override
  int get hashCode => Object.hash(at, txRate, rxRate);
}

class TunEventLog {
  const TunEventLog({required this.time, required this.message});

  final String time;
  final String message;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TunEventLog && other.time == time && other.message == message;
  }

  @override
  int get hashCode => Object.hash(time, message);
}

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
    this.adapterName = 'TUN 虚拟网卡',
    required this.state,
    required this.permission,
    required this.cpe,
    this.helperInstalled = false,
    this.traffic = const TrafficStats(),
    this.lastError,
  });

  factory TunStatus.defaults({String cpeHost = '192.168.1.140'}) {
    return TunStatus(
      mode: TunMode.tun,
      adapterName: 'TUN 虚拟网卡',
      state: TunState.stopped,
      permission: TunPermission.needsVpnConsent,
      cpe: CpeHealth(host: cpeHost, reachable: false),
    );
  }

  final TunMode mode;
  final String adapterName;
  final TunState state;
  final TunPermission permission;
  final CpeHealth cpe;
  final bool helperInstalled;
  final TrafficStats traffic;
  final String? lastError;

  TunStatus copyWith({
    TunMode? mode,
    String? adapterName,
    TunState? state,
    TunPermission? permission,
    CpeHealth? cpe,
    bool? helperInstalled,
    TrafficStats? traffic,
    Object? lastError = _unset,
  }) {
    return TunStatus(
      mode: mode ?? this.mode,
      adapterName: adapterName ?? this.adapterName,
      state: state ?? this.state,
      permission: permission ?? this.permission,
      cpe: cpe ?? this.cpe,
      helperInstalled: helperInstalled ?? this.helperInstalled,
      traffic: traffic ?? this.traffic,
      lastError: lastError == _unset ? this.lastError : lastError as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TunStatus &&
            other.mode == mode &&
            other.adapterName == adapterName &&
            other.state == state &&
            other.permission == permission &&
            other.cpe == cpe &&
            other.helperInstalled == helperInstalled &&
            other.traffic == traffic &&
            other.lastError == lastError;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    adapterName,
    state,
    permission,
    cpe,
    helperInstalled,
    traffic,
    lastError,
  );
}
