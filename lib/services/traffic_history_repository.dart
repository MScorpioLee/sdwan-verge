import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../tun/traffic_history_store.dart';
import '../tun/tun_models.dart';

class TrafficHistoryRepository implements TrafficHistoryStore {
  static const storageKey = 'sdwan_traffic_history_v1';
  static const maxSamples = 120;

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  @override
  Future<List<TrafficSample>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final samples = <TrafficSample>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, Object?>.from(item);
        final at = DateTime.tryParse(map['at']?.toString() ?? '');
        if (at == null) {
          continue;
        }
        samples.add(
          TrafficSample(
            at: at,
            txRate: _intFromValue(map['txRate']),
            rxRate: _intFromValue(map['rxRate']),
          ),
        );
      }
      return samples.length > maxSamples
          ? samples.sublist(samples.length - maxSamples)
          : samples;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<TrafficSample> samples) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = samples.length > maxSamples
        ? samples.sublist(samples.length - maxSamples)
        : samples;
    final payload = [
      for (final sample in capped)
        {
          'at': sample.at.toIso8601String(),
          'txRate': sample.txRate,
          'rxRate': sample.rxRate,
        },
    ];
    await prefs.setString(storageKey, jsonEncode(payload));
  }

  int _intFromValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
