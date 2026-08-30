import 'package:hive_test/hive_test.dart';

class HiveTestHelper {
  /// Call in setUp() — spins up in-memory Hive, no disk I/O
  static Future<void> setUp() async {
    await setUpTestHive();
  }

  /// Call in tearDown() — wipes everything clean between tests
  static Future<void> tearDown() async {
    await tearDownTestHive();
  }
}
