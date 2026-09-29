import 'package:athlete_os/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog IDs stay unique and every item can be filtered', () async {
    await loadCatalog();
    final ids = builtInExercises.map((item) => item['id']).toList();
    expect(ids.length, ids.toSet().length);
    expect(ids.length, greaterThanOrEqualTo(50));
    for (final item in builtInExercises) {
      expect(item['id'], isNotEmpty);
      expect(item['name'], isNotEmpty);
      expect(item['muscle'], isNotEmpty);
      expect(item['equipment'], isNotEmpty);
    }
  });
}
