import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdwan_client/services/traffic_history_repository.dart';
import 'package:sdwan_client/tun/tun_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves loads and clears traffic samples', () async {
    final repository = TrafficHistoryRepository();
    final sample = TrafficSample(
      at: DateTime(2026, 6, 4, 12),
      txRate: 12,
      rxRate: 34,
      rttMs: 188,
    );

    await repository.save([sample]);
    final loaded = await repository.load();

    expect(loaded, [sample]);

    await repository.clear();

    expect(await repository.load(), isEmpty);
  });
}
