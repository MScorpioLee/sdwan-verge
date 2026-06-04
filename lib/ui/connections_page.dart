import 'package:flutter/material.dart';

import '../tun/tun_controller.dart';
import '../tun/tun_models.dart';
import 'theme.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key, required this.tunController});

  final TunController tunController;

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  static const _protocols = ['全部', 'TCP', 'UDP', 'ICMP', 'DNS'];

  String _query = '';
  String _protocol = '全部';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tunController.refreshConnections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.tunController,
      builder: (context, _) {
        final connections = widget.tunController.connections;
        final filteredConnections = connections.where(_matchesFilter).toList();
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Row(
              children: [
                const Text(
                  '连接统计',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.tunController.refreshConnections,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.textSecondary,
                  tooltip: '刷新连接',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _FilterBar(
              query: _query,
              protocol: _protocol,
              protocols: _protocols,
              onQueryChanged: (value) => setState(() => _query = value),
              onProtocolChanged: (value) {
                if (value != null) {
                  setState(() => _protocol = value);
                }
              },
            ),
            const SizedBox(height: 18),
            _SummaryRow(connections: filteredConnections),
            const SizedBox(height: 18),
            _BandwidthChartCard(samples: widget.tunController.trafficSamples),
            const SizedBox(height: 18),
            _DomainStatsCard(connections: filteredConnections),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: panelDecoration(),
              child: filteredConnections.isEmpty
                  ? const _EmptyConnections()
                  : Column(
                      children: [
                        for (final connection in filteredConnections.take(80))
                          _ConnectionTile(connection: connection),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _matchesFilter(TunConnection connection) {
    final matchesProtocol = switch (_protocol) {
      '全部' => true,
      'DNS' => connection.dnsRedirect || _portOf(connection.target) == '53',
      _ => connection.proto.toUpperCase() == _protocol,
    };
    if (!matchesProtocol) {
      return false;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return [
      connection.proto,
      connection.domain ?? '',
      connection.source,
      connection.target,
      connection.via,
    ].any((value) => value.toLowerCase().contains(query));
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.protocol,
    required this.protocols,
    required this.onQueryChanged,
    required this.onProtocolChanged,
  });

  final String query;
  final String protocol;
  final List<String> protocols;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onProtocolChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                labelText: '筛选域名或 IP',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),
          ),
          for (final item in protocols)
            ChoiceChip(
              label: Text(item),
              selected: protocol == item,
              onSelected: (_) => onProtocolChanged(item),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.connections});

  final List<TunConnection> connections;

  @override
  Widget build(BuildContext context) {
    final txRate = connections.fold<int>(
      0,
      (total, connection) => total + connection.txRate,
    );
    final rxRate = connections.fold<int>(
      0,
      (total, connection) => total + connection.rxRate,
    );
    final dnsCount = connections
        .where((connection) => connection.dnsRedirect)
        .length;

    return Row(
      children: [
        Expanded(
          child: _MetricCard(label: '连接数', value: '${connections.length}'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(label: 'DNS 到 CPE', value: '$dnsCount'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(label: '实时上行', value: _formatRate(txRate)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(label: '实时下行', value: _formatRate(rxRate)),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BandwidthChartCard extends StatelessWidget {
  const _BandwidthChartCard({required this.samples});

  final List<TrafficSample> samples;

  @override
  Widget build(BuildContext context) {
    final latest = samples.isEmpty ? null : samples.last;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '带宽趋势',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _Legend(color: AppColors.primary, label: '上行'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.success, label: '下行'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: _BandwidthChartPainter(samples: samples),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            latest == null
                ? '等待采样'
                : '当前 ↑ ${_formatRate(latest.txRate)}  ↓ ${_formatRate(latest.rxRate)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _BandwidthChartPainter extends CustomPainter {
  const _BandwidthChartPainter({required this.samples});

  final List<TrafficSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (samples.isEmpty) {
      return;
    }

    final visible = samples.length > 60
        ? samples.sublist(samples.length - 60)
        : samples;
    final maxRate = visible
        .fold<int>(
          1,
          (max, sample) => [
            max,
            sample.txRate,
            sample.rxRate,
          ].reduce((a, b) => a > b ? a : b),
        )
        .toDouble();

    Path lineFor(int Function(TrafficSample sample) selector) {
      final path = Path();
      for (var i = 0; i < visible.length; i++) {
        final x = visible.length == 1
            ? size.width
            : size.width * i / (visible.length - 1);
        final y =
            size.height -
            (selector(visible[i]).clamp(0, maxRate.toInt()) / maxRate) *
                size.height;
        final point = Offset(x, y);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path;
    }

    final txPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rxPaint = Paint()
      ..color = AppColors.success
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(lineFor((sample) => sample.txRate), txPaint);
    canvas.drawPath(lineFor((sample) => sample.rxRate), rxPaint);
  }

  @override
  bool shouldRepaint(covariant _BandwidthChartPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}

class _DomainStatsCard extends StatelessWidget {
  const _DomainStatsCard({required this.connections});

  final List<TunConnection> connections;

  @override
  Widget build(BuildContext context) {
    final stats = _domainStats(connections);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '域名统计',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            const _EmptyConnections()
          else
            for (final stat in stats.take(12)) _DomainStatRow(stat: stat),
        ],
      ),
    );
  }
}

class _DomainStatRow extends StatelessWidget {
  const _DomainStatRow({required this.stat});

  final _DomainStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stat.domain,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${stat.count} 条',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 168,
            child: Text(
              '↑ ${_formatRate(stat.txRate)}  ↓ ${_formatRate(stat.rxRate)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 168,
            child: Text(
              '累计 ↑ ${_formatBytes(stat.txBytes)}  ↓ ${_formatBytes(stat.rxBytes)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.connection});

  final TunConnection connection;

  @override
  Widget build(BuildContext context) {
    final domain = connection.domain;
    final hasDomain = domain != null && domain.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              connection.proto,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasDomain ? domain : connection.target,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${hasDomain ? '${connection.target}  ' : ''}'
                  '入口 ${connection.source}  出口 ${connection.via}'
                  '${connection.dnsRedirect ? '  DNS->CPE' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '↑ ${_formatRate(connection.txRate)}  '
                  '↓ ${_formatRate(connection.rxRate)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '累计 ↑ ${_formatBytes(connection.txBytes)}  '
                  '↓ ${_formatBytes(connection.rxBytes)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          '暂无连接',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _DomainStat {
  const _DomainStat({
    required this.domain,
    required this.count,
    required this.txBytes,
    required this.rxBytes,
    required this.txRate,
    required this.rxRate,
  });

  final String domain;
  final int count;
  final int txBytes;
  final int rxBytes;
  final int txRate;
  final int rxRate;
}

List<_DomainStat> _domainStats(List<TunConnection> connections) {
  final stats = <String, _MutableDomainStat>{};
  for (final connection in connections) {
    final key = _domainKey(connection);
    stats.putIfAbsent(key, () => _MutableDomainStat(key)).add(connection);
  }
  final values = [
    for (final stat in stats.values)
      _DomainStat(
        domain: stat.domain,
        count: stat.count,
        txBytes: stat.txBytes,
        rxBytes: stat.rxBytes,
        txRate: stat.txRate,
        rxRate: stat.rxRate,
      ),
  ];
  values.sort((a, b) {
    final rateCompare = (b.txRate + b.rxRate).compareTo(a.txRate + a.rxRate);
    if (rateCompare != 0) {
      return rateCompare;
    }
    return (b.txBytes + b.rxBytes).compareTo(a.txBytes + a.rxBytes);
  });
  return values;
}

class _MutableDomainStat {
  _MutableDomainStat(this.domain);

  final String domain;
  int count = 0;
  int txBytes = 0;
  int rxBytes = 0;
  int txRate = 0;
  int rxRate = 0;

  void add(TunConnection connection) {
    count += 1;
    txBytes += connection.txBytes;
    rxBytes += connection.rxBytes;
    txRate += connection.txRate;
    rxRate += connection.rxRate;
  }
}

String _domainKey(TunConnection connection) {
  final domain = connection.domain;
  if (domain != null && domain.isNotEmpty) {
    return domain;
  }
  return _hostOf(connection.target);
}

String _hostOf(String endpoint) {
  final bracketEnd = endpoint.indexOf(']');
  if (endpoint.startsWith('[') && bracketEnd > 0) {
    return endpoint.substring(1, bracketEnd);
  }
  final parts = endpoint.split(':');
  if (parts.length > 1) {
    return parts.first;
  }
  return endpoint;
}

String? _portOf(String endpoint) {
  final index = endpoint.lastIndexOf(':');
  if (index < 0 || index == endpoint.length - 1) {
    return null;
  }
  return endpoint.substring(index + 1);
}

String _formatRate(int bytesPerSecond) => '${_formatBytes(bytesPerSecond)}/s';

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
}
