import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('mergeCartQuantities (pure guest -> account merge)', () {
    int cap(String id) => switch (id) {
          'a' => 12,
          'b' => 2,
          'gone' => 0, // unavailable / out of stock
          _ => 0, // unknown product
        };

    test('sums quantities per product, clamped to the cap', () {
      final merged = mergeCartQuantities(
        {'a': 2, 'b': 1},
        {'a': 1, 'b': 2},
        cap,
      );
      expect(merged, {'a': 3, 'b': 2}); // b: 1+2=3 clamped to 2
    });

    test('drops products the live catalogue does not allow', () {
      final merged = mergeCartQuantities(
        {'a': 2, 'gone': 5, 'nope': 1},
        {'gone': 2},
        cap,
      );
      expect(merged, {'a': 2});
    });

    test('account-only items survive; empty carts merge to empty', () {
      expect(mergeCartQuantities({}, {'a': 4}, cap), {'a': 4});
      expect(mergeCartQuantities({}, {}, cap), isEmpty);
    });

    test('garbage quantities (zero/negative) never enter the merged cart', () {
      final merged = mergeCartQuantities(
        {'a': 0},
        {'a': -3, 'b': 1},
        cap,
      );
      expect(merged, {'b': 1});
    });
  });

  group('CartRepository merge/replace against the real catalogue', () {
    // LocalProductRepository: fresh-oyster-250 has stock 40 (cap 12),
    // oyster-pickle-250 is unavailable (cap 0).
    test('mergeRemote clamps and drops, then persists the merged cart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = CartRepository(prefs, LocalProductRepository());
      await repo.load();
      await repo.add('fresh-oyster-250', 2);

      final merged = await repo.mergeRemote({
        'fresh-oyster-250': 1,
        'oyster-pickle-250': 3,
        'not-a-product': 7,
      });

      expect(merged, {'fresh-oyster-250': 3});
      expect(repo.items, {'fresh-oyster-250': 3});
    });

    test('replaceAll re-sanitises a remote snapshot on apply', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = CartRepository(prefs, LocalProductRepository());
      await repo.load();
      await repo.add('fresh-oyster-500', 1);

      await repo.replaceAll({
        'fresh-oyster-500': 99, // clamped to 12
        'oyster-pickle-250': 4, // unavailable -> dropped
        'unknown': 2,
      });

      expect(repo.items, {'fresh-oyster-500': 12});
    });
  });
}
