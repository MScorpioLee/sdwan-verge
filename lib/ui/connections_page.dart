import 'dart:math' as math;

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
            _BandwidthChartCard(
              samples: widget.tunController.trafficSamples,
              cpeHost: widget.tunController.status.cpe.host,
            ),
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

enum _ChartAggregate { average, peak }

enum _ChartRange { hour, day }

class _BandwidthChartCard extends StatefulWidget {
  const _BandwidthChartCard({required this.samples, required this.cpeHost});

  final List<TrafficSample> samples;
  final String cpeHost;

  @override
  State<_BandwidthChartCard> createState() => _BandwidthChartCardState();
}

class _BandwidthChartCardState extends State<_BandwidthChartCard> {
  _ChartAggregate _aggregate = _ChartAggregate.average;
  _ChartRange _range = _ChartRange.hour;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleSamples(widget.samples, _range);
    final chartSamples = _aggregate == _ChartAggregate.average
        ? _smoothedSamples(visible)
        : visible;
    final tooltipSample =
        _hoverIndex == null ||
            _hoverIndex! < 0 ||
            _hoverIndex! >= chartSamples.length
        ? null
        : chartSamples[_hoverIndex!];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartHeader(
            aggregate: _aggregate,
            range: _range,
            onAggregateChanged: (value) => setState(() {
              _aggregate = value;
              _hoverIndex = null;
            }),
            onRangeChanged: (value) => setState(() {
              _range = value;
              _hoverIndex = null;
            }),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _range == _ChartRange.day ? 245 : 220,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  onHover: (event) => _setHover(event.localPosition, size),
                  onExit: (_) => setState(() => _hoverIndex = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _setHover(details.localPosition, size),
                    onPanDown: (details) =>
                        _setHover(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _setHover(details.localPosition, size),
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: size,
                          painter: _IkuaiBandwidthChartPainter(
                            samples: chartSamples,
                            hoverIndex: _hoverIndex,
                          ),
                        ),
                        if (tooltipSample != null)
                          _ChartTooltip(
                            sample: tooltipSample,
                            aggregate: _aggregate,
                            left: _tooltipLeft(
                              size,
                              _hoverIndex!,
                              chartSamples,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.hub_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'CPE ${widget.cpeHost}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'TUN',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  void _setHover(Offset position, Size size) {
    final visible = _visibleSamples(widget.samples, _range);
    final chartSamples = _aggregate == _ChartAggregate.average
        ? _smoothedSamples(visible)
        : visible;
    if (chartSamples.isEmpty) {
      return;
    }
    final rect = _IkuaiBandwidthChartPainter.chartRect(size);
    if (!rect.inflate(12).contains(position)) {
      if (_hoverIndex != null) {
        setState(() => _hoverIndex = null);
      }
      return;
    }
    final ratio = ((position.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final index = (ratio * (chartSamples.length - 1)).round();
    if (_hoverIndex != index) {
      setState(() => _hoverIndex = index);
    }
  }

  double _tooltipLeft(Size size, int index, List<TrafficSample> samples) {
    final rect = _IkuaiBandwidthChartPainter.chartRect(size);
    final x = samples.length <= 1
        ? rect.right
        : rect.left + rect.width * index / (samples.length - 1);
    return (x + 10).clamp(0.0, math.max(0, size.width - 174));
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.aggregate,
    required this.range,
    required this.onAggregateChanged,
    required this.onRangeChanged,
  });

  final _ChartAggregate aggregate;
  final _ChartRange range;
  final ValueChanged<_ChartAggregate> onAggregateChanged;
  final ValueChanged<_ChartRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ChartMenuButton<_ChartAggregate>(
              value: aggregate,
              label: _aggregateText(aggregate),
              items: const {
                _ChartAggregate.average: '平均值',
                _ChartAggregate.peak: '峰值',
              },
              onSelected: onAggregateChanged,
            ),
            _ChartMenuButton<String>(
              value: 'all',
              label: '全部',
              items: const {'all': '全部'},
              onSelected: (_) {},
            ),
            _RangeToggle(value: range, onChanged: onRangeChanged),
          ],
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ChartTitle(),
              const SizedBox(height: 12),
              controls,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [const _ChartTitle(), const Spacer(), controls],
        );
      },
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '上下行速率',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _ChartMenuButton<T> extends StatelessWidget {
  const _ChartMenuButton({
    required this.value,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final T value;
  final String label;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in items.entries)
          PopupMenuItem<T>(value: entry.key, child: Text(entry.value)),
      ],
      offset: const Offset(0, 38),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: value == _ChartAggregate.peak
                ? AppColors.primary
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 7),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.value, required this.onChanged});

  final _ChartRange value;
  final ValueChanged<_ChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeButton(
            label: '1小时',
            selected: value == _ChartRange.hour,
            onTap: () => onChanged(_ChartRange.hour),
          ),
          _RangeButton(
            label: '24小时',
            selected: value == _ChartRange.day,
            onTap: () => onChanged(_ChartRange.day),
          ),
        ],
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({
    required this.sample,
    required this.aggregate,
    required this.left,
  });

  final TrafficSample sample;
  final _ChartAggregate aggregate;
  final double left;

  @override
  Widget build(BuildContext context) {
    final prefix = _aggregateText(aggregate);
    return Positioned(
      left: left,
      top: 10,
      child: Container(
        width: 164,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xD9232D36),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            height: 1.55,
            fontWeight: FontWeight.w700,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTooltipTime(sample.at),
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 5),
              Text('$prefix上行：${_formatRate(sample.txRate)}'),
              Text('$prefix下行：${_formatRate(sample.rxRate)}'),
              if (sample.rttMs != null) Text('平均延迟：${sample.rttMs} ms'),
            ],
          ),
        ),
      ),
    );
  }
}

class _IkuaiBandwidthChartPainter extends CustomPainter {
  const _IkuaiBandwidthChartPainter({
    required this.samples,
    required this.hoverIndex,
  });

  final List<TrafficSample> samples;
  final int? hoverIndex;

  static Rect chartRect(Size size) => Rect.fromLTWH(
    24,
    28,
    math.max(1, size.width - 74),
    math.max(1, size.height - 60),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = chartRect(size);
    _drawAxisTitles(canvas, rect);
    _drawGrid(canvas, rect);
    _drawXAxis(canvas, rect);
    if (samples.isEmpty) {
      _drawEmpty(canvas, rect);
      return;
    }

    final maxRate = _niceMaxRate(samples);
    final maxRtt = _niceMaxRtt(samples);
    _drawYAxis(canvas, rect, maxRate);
    final txPoints = _pointsFor(
      samples,
      rect,
      maxRate,
      (sample) => sample.txRate,
    );
    final rxPoints = _pointsFor(
      samples,
      rect,
      maxRate,
      (sample) => sample.rxRate,
    );
    _drawLine(canvas, txPoints, const Color(0xFF8C8AE8), rect);
    _drawLine(canvas, rxPoints, const Color(0xFF74B889), rect);
    final rttPoints = _rttPointsFor(samples, rect, maxRtt);
    _drawRttLine(canvas, rttPoints, rect);
    _drawHover(canvas, rect, maxRate, maxRtt);
  }

  void _drawAxisTitles(Canvas canvas, Rect rect) {
    if (samples.any((sample) => sample.rttMs != null)) {
      _drawText(
        canvas,
        '延迟ms',
        Offset(rect.left - 2, 0),
        color: AppColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
    }
    _drawText(
      canvas,
      '速率',
      Offset(rect.right + 12, 0),
      color: AppColors.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      align: TextAlign.right,
    );
  }

  void _drawGrid(Canvas canvas, Rect rect) {
    final grid = Paint()
      ..color = const Color(0xFFEAEFF5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final y = rect.top + rect.height * i / 5;
      _drawDashedLine(
        canvas,
        Offset(rect.left, y),
        Offset(rect.right, y),
        grid,
      );
    }
    final axis = Paint()
      ..color = const Color(0xFFDDE4EC)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.bottom),
      axis,
    );
  }

  void _drawYAxis(Canvas canvas, Rect rect, int maxRate) {
    final maxRtt = _niceMaxRtt(samples);
    final hasRtt = samples.any((sample) => sample.rttMs != null);
    for (var i = 0; i <= 5; i++) {
      final ratio = i / 5;
      final y = rect.bottom - rect.height * ratio;
      final rate = (maxRate * ratio).round();
      if (hasRtt) {
        _drawText(
          canvas,
          '${(maxRtt * ratio).round()}',
          Offset(0, y - 7),
          color: AppColors.textSecondary,
          fontSize: 11,
        );
      }
      _drawText(
        canvas,
        _formatBytes(rate),
        Offset(rect.right + 12, y - 7),
        color: AppColors.textSecondary,
        fontSize: 11,
      );
    }
  }

  void _drawXAxis(Canvas canvas, Rect rect) {
    if (samples.isEmpty) {
      return;
    }
    final labelCount = samples.length < 6 ? samples.length : 6;
    for (var i = 0; i < labelCount; i++) {
      final sampleIndex = labelCount == 1
          ? samples.length - 1
          : (i * (samples.length - 1) / (labelCount - 1)).round();
      final x = labelCount == 1
          ? rect.right
          : rect.left + rect.width * i / (labelCount - 1);
      _drawText(
        canvas,
        _formatAxisTime(samples[sampleIndex].at),
        Offset(x - 16, rect.bottom + 10),
        color: AppColors.textSecondary,
        fontSize: 11,
      );
    }
  }

  List<Offset> _pointsFor(
    List<TrafficSample> samples,
    Rect rect,
    int maxRate,
    int Function(TrafficSample sample) selector,
  ) {
    return [
      for (var i = 0; i < samples.length; i++)
        Offset(
          samples.length == 1
              ? rect.right
              : rect.left + rect.width * i / (samples.length - 1),
          rect.bottom -
              rect.height * (selector(samples[i]).clamp(0, maxRate) / maxRate),
        ),
    ];
  }

  List<Offset> _rttPointsFor(
    List<TrafficSample> samples,
    Rect rect,
    int maxRtt,
  ) {
    final points = <Offset>[];
    for (var i = 0; i < samples.length; i++) {
      final rtt = samples[i].rttMs;
      if (rtt == null) {
        continue;
      }
      points.add(
        Offset(
          samples.length == 1
              ? rect.right
              : rect.left + rect.width * i / (samples.length - 1),
          rect.bottom - rect.height * (rtt.clamp(0, maxRtt) / maxRtt),
        ),
      );
    }
    return points;
  }

  void _drawLine(Canvas canvas, List<Offset> points, Color color, Rect rect) {
    if (points.isEmpty) {
      return;
    }
    final fill = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = _smoothPath(points);
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, rect.bottom)
      ..lineTo(points.first.dx, rect.bottom)
      ..close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, stroke);
  }

  void _drawRttLine(Canvas canvas, List<Offset> points, Rect rect) {
    if (points.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = const Color(0xFF66A8FF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = _smoothPath(points);
    canvas.drawPath(path, paint);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      return path;
    }
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void _drawHover(Canvas canvas, Rect rect, int maxRate, int maxRtt) {
    final index = hoverIndex;
    if (index == null || index < 0 || index >= samples.length) {
      return;
    }
    final x = samples.length <= 1
        ? rect.right
        : rect.left + rect.width * index / (samples.length - 1);
    final guide = Paint()
      ..color = const Color(0xFF6B7280).withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), guide);
    for (final point in [
      _pointAt(samples[index].txRate, x, rect, maxRate),
      _pointAt(samples[index].rxRate, x, rect, maxRate),
      if (samples[index].rttMs != null)
        _pointAt(samples[index].rttMs!, x, rect, maxRtt),
    ]) {
      canvas.drawCircle(
        point,
        4,
        Paint()..color = const Color(0xFF5B6EE1).withValues(alpha: 0.22),
      );
      canvas.drawCircle(point, 2.4, Paint()..color = const Color(0xFF5B6EE1));
    }
  }

  Offset _pointAt(int rate, double x, Rect rect, int maxRate) {
    return Offset(
      x,
      rect.bottom - rect.height * (rate.clamp(0, maxRate) / maxRate),
    );
  }

  void _drawEmpty(Canvas canvas, Rect rect) {
    _drawText(
      canvas,
      '等待采样',
      Offset(rect.center.dx - 28, rect.center.dy - 8),
      color: AppColors.textSecondary,
      fontSize: 12,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 5.0;
    const gap = 5.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) {
      return;
    }
    final direction = Offset(dx / distance, dy / distance);
    var drawn = 0.0;
    while (drawn < distance) {
      final segmentStart = start + direction * drawn;
      final segmentEnd = start + direction * math.min(drawn + dash, distance);
      canvas.drawLine(segmentStart, segmentEnd, paint);
      drawn += dash + gap;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w500,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _IkuaiBandwidthChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.hoverIndex != hoverIndex;
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

List<TrafficSample> _visibleSamples(
  List<TrafficSample> samples,
  _ChartRange range,
) {
  if (samples.isEmpty) {
    return const [];
  }
  final cutoff = samples.last.at.subtract(
    range == _ChartRange.hour
        ? const Duration(hours: 1)
        : const Duration(hours: 24),
  );
  final visible = samples
      .where((sample) => !sample.at.isBefore(cutoff))
      .toList();
  if (visible.isNotEmpty) {
    return visible;
  }
  return samples.length > 80 ? samples.sublist(samples.length - 80) : samples;
}

List<TrafficSample> _smoothedSamples(List<TrafficSample> samples) {
  if (samples.length < 3) {
    return samples;
  }
  return [
    for (var i = 0; i < samples.length; i++)
      TrafficSample(
        at: samples[i].at,
        txRate: _averageAround(samples, i, (sample) => sample.txRate),
        rxRate: _averageAround(samples, i, (sample) => sample.rxRate),
        rttMs: _averageNullableAround(samples, i, (sample) => sample.rttMs),
      ),
  ];
}

int _averageAround(
  List<TrafficSample> samples,
  int index,
  int Function(TrafficSample sample) selector,
) {
  final start = math.max(0, index - 1);
  final end = math.min(samples.length - 1, index + 1);
  var total = 0;
  var count = 0;
  for (var i = start; i <= end; i++) {
    total += selector(samples[i]);
    count += 1;
  }
  return count == 0 ? 0 : (total / count).round();
}

int? _averageNullableAround(
  List<TrafficSample> samples,
  int index,
  int? Function(TrafficSample sample) selector,
) {
  final start = math.max(0, index - 1);
  final end = math.min(samples.length - 1, index + 1);
  var total = 0;
  var count = 0;
  for (var i = start; i <= end; i++) {
    final value = selector(samples[i]);
    if (value == null) {
      continue;
    }
    total += value;
    count += 1;
  }
  return count == 0 ? null : (total / count).round();
}

int _niceMaxRate(List<TrafficSample> samples) {
  final maxRate = samples.fold<int>(
    1,
    (maxRate, sample) =>
        math.max(maxRate, math.max(sample.txRate, sample.rxRate)),
  );
  final padded = (maxRate * 1.25).ceil();
  const steps = [
    1024,
    2 * 1024,
    5 * 1024,
    10 * 1024,
    20 * 1024,
    50 * 1024,
    100 * 1024,
    200 * 1024,
    500 * 1024,
    1024 * 1024,
    2 * 1024 * 1024,
    5 * 1024 * 1024,
    10 * 1024 * 1024,
    20 * 1024 * 1024,
    50 * 1024 * 1024,
  ];
  for (final step in steps) {
    if (padded <= step) {
      return step;
    }
  }
  return padded;
}

int _niceMaxRtt(List<TrafficSample> samples) {
  final maxRtt = samples.fold<int>(
    1,
    (maxRtt, sample) => math.max(maxRtt, sample.rttMs ?? 0),
  );
  final padded = (maxRtt * 1.25).ceil();
  const steps = [50, 100, 200, 400, 800, 1200, 2000, 5000];
  for (final step in steps) {
    if (padded <= step) {
      return step;
    }
  }
  return padded;
}

String _aggregateText(_ChartAggregate aggregate) {
  return switch (aggregate) {
    _ChartAggregate.average => '平均值',
    _ChartAggregate.peak => '峰值',
  };
}

String _formatAxisTime(DateTime time) {
  return '${_two(time.hour)}:${_two(time.minute)}';
}

String _formatTooltipTime(DateTime time) {
  return '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

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
