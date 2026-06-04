import 'tun_models.dart';

abstract interface class TrafficHistoryStore {
  Future<List<TrafficSample>> load();

  Future<void> save(List<TrafficSample> samples);

  Future<void> clear();
}
