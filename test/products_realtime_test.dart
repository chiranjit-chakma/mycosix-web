import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/product.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/products_controller.dart';

Product _p(String id, {double price = 10}) => Product(
      id: id,
      name: 'Test $id',
      description: 'Desc',
      category: 'Fresh',
      image: 'assets/products/oyster_bouquet.jpg',
      variant: 'Fresh',
      weight: '250 g',
      price: price,
      stock: 5,
      available: true,
    );

/// A repository that also streams catalogue changes, like the production
/// Firestore-backed one. The controller must subscribe and push updates.
class _FakeLiveSource implements ProductRepository, ProductStreamSource {
  _FakeLiveSource(this.initial);

  List<Product> initial;
  final StreamController<List<Product>> _ctrl =
      StreamController<List<Product>>.broadcast();
  int fetchCount = 0;

  @override
  Future<List<Product>> fetchAll() async {
    fetchCount++;
    return initial;
  }

  @override
  Future<Product?> fetchById(String id) async => null;

  @override
  Future<List<Product>> fetchByCategory(String category) async => const [];

  @override
  Stream<List<Product>> watchAll() => _ctrl.stream;

  void push(List<Product> next) => _ctrl.add(next);

  Future<void> close() => _ctrl.close();
}

void main() {
  test('live repository pushes reach listeners after the first load', () async {
    final repo = _FakeLiveSource([_p('a', price: 10)]);
    final controller = ProductsController(repo);

    final first = await controller.fetchAll();
    expect(first.single.price, 10);
    expect(controller.loaded, isTrue);

    var notifications = 0;
    controller.addListener(() => notifications++);

    // Admin adds a product and edits another — Firestore pushes a snapshot.
    repo.push([_p('a', price: 11), _p('b', price: 20)]);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, greaterThan(0));
    expect(controller.products.length, 2);
    expect(controller.products.first.price, 11);

    controller.dispose();
    await repo.close();
  });

  test('dispose cancels the subscription (no updates after dispose)', () async {
    final repo = _FakeLiveSource([_p('a')]);
    final controller = ProductsController(repo);
    await controller.fetchAll();

    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();

    repo.push([_p('a', price: 99)]);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 0);
    await repo.close();
  });

  test('concurrent first loads share a single fetch', () async {
    final repo = _FakeLiveSource([_p('a')]);
    final controller = ProductsController(repo);

    final f1 = controller.fetchAll();
    final f2 = controller.fetchAll();
    await Future.wait([f1, f2]);

    expect(repo.fetchCount, 1);
    controller.dispose();
    await repo.close();
  });

  test('repositories without a live source keep load-once behaviour', () async {
    final repo = LocalProductRepository();
    final controller = ProductsController(repo);

    final first = await controller.fetchAll();
    final second = await controller.fetchAll();
    expect(first, same(second)); // cached, not re-fetched
    expect(controller.loaded, isTrue);
    expect(controller.products.length, 6); // bundled catalogue
    controller.dispose();
  });
}
