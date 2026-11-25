import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_mobile/main.dart';
import 'package:warehouse_mobile/warehouse_api.dart';

// Models the server independently of the widget tree and the current session.
class TestWarehouse extends WarehouseApi {
  TestWarehouse(this.rows) : super('https://warehouse.invalid');

  final List<Item> rows;
  bool online = true;

  @override
  Future<void> login(String user, String pass) async {
    if (user != 'admin' || pass != 'test-password') {
      throw const WarehouseApiException('Проверьте имя и пароль.');
    }
    username = user;
  }

  @override
  Future<List<Item>> listItems() async {
    if (!online) throw const WarehouseApiException('Нет соединения');
    return List.of(rows);
  }

  @override
  Future<CatalogReferences> references() async => const CatalogReferences(
    categories: [CatalogEntry(id: 1, name: 'Канцелярия')],
    suppliers: [CatalogEntry(id: 2, name: 'Алматы')],
  );

  @override
  Future<Item> createItem(ItemInput input) async {
    final id = rows.fold(0, (max, row) => row.id > max ? row.id : max) + 1;
    final item = Item.fromJson({'id': id, ...input.toJson()});
    rows.add(item);
    return item;
  }

  @override
  Future<Item> updateItem(int id, ItemInput input) async {
    final index = rows.indexWhere((item) => item.id == id);
    final updated = Item.fromJson({'id': id, ...input.toJson()});
    rows[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteItem(int id) async => rows.removeWhere((i) => i.id == id);
}

const pencil = Item(id: 1, name: 'Карандаш', price: 30, quantity: 2, categoryId: 1, supplierId: 2);
const paper = Item(id: 2, name: 'Бумага', price: 40, quantity: 3, categoryId: 1, supplierId: 2);

Finder field(String key) => find.byKey(Key(key));

Future<void> tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> login(WidgetTester t, TestWarehouse api) async {
  await t.pumpWidget(WarehouseApp(api: api));
  await t.enterText(field('username'), 'admin');
  await t.enterText(field('password'), 'test-password');
  await tap(t, find.text('Войти'));
}

Future<void> catalog(WidgetTester t, TestWarehouse api) async {
  await login(t, api);
  await tap(t, find.text('Товары'));
}

Future<void> create(WidgetTester t) async {
  await tap(t, find.text('Добавить товар'));
  await t.enterText(field('name'), 'Маркер');
  await t.enterText(field('price'), '12,5');
  await t.enterText(field('quantity'), '4');
  await tap(t, find.text('Сохранить'));
}

void main() {
  late TestWarehouse api;
  setUp(() => api = TestWarehouse([pencil, paper]));

  testWidgets('TC01 — запуск и загрузка остатков после входа', (t) async {
    await login(t, api);
    expect(find.text('Остаток на складе'), findsOneWidget);
    expect(find.text('5 шт.'), findsOneWidget);
  });

  testWidgets('TC02 — ввод логина и скрытого пароля', (t) async {
    await t.pumpWidget(WarehouseApp(api: api));
    await t.enterText(field('username'), 'admin');
    await t.enterText(field('password'), 'bad-password');
    final passwordField = find.descendant(of: field('password'), matching: find.byType(EditableText));
    expect(t.widget<EditableText>(passwordField).obscureText, isTrue);
    await tap(t, find.text('Войти'));
    expect(find.text('Проверьте имя и пароль.'), findsOneWidget);
    await t.enterText(field('password'), 'test-password');
    await tap(t, find.text('Войти'));
    expect(api.username, 'admin');
    expect(find.text('Каталог товаров'), findsOneWidget);
  });

  testWidgets('TC03 — пустое название и неверные числовые поля', (t) async {
    await catalog(t, api);
    await tap(t, find.text('Добавить товар'));
    await t.enterText(field('price'), '-3');
    await t.enterText(field('quantity'), '1.5');
    await tap(t, find.text('Сохранить'));
    expect(find.text('Введите название'), findsOneWidget);
    expect(find.text('Введите неотрицательную цену'), findsOneWidget);
    expect(find.text('Введите целое число от нуля'), findsOneWidget);
    expect(api.rows.length, 2);
  });

  testWidgets('TC04 — создание товара', (t) async {
    await catalog(t, api);
    await create(t);
    expect(find.text('Маркер'), findsOneWidget);
    final added = api.rows.singleWhere((i) => i.name == 'Маркер');
    expect(added.price, 12.5);
    expect(added.quantity, 4);
    expect(added.categoryId, 1);
    expect(added.supplierId, 2);
  });

  testWidgets('TC05 — отмена и подтверждение удаления', (t) async {
    await catalog(t, api);
    Future<void> openDialog() async {
      await tap(t, find.byTooltip('Действия: Карандаш'));
      await tap(t, find.text('Удалить'));
      expect(find.text('Удалить товар?'), findsOneWidget);
    }
    await openDialog();
    await tap(t, find.text('Отмена'));
    expect(api.rows, contains(pencil));
    await openDialog();
    await tap(t, find.text('Удалить'));
    expect(find.text('Карандаш'), findsNothing);
    expect(api.rows, [paper]);
  });

  testWidgets('TC06 — изменение существующего товара', (t) async {
    await catalog(t, api);
    await tap(t, find.byTooltip('Действия: Карандаш'));
    await tap(t, find.text('Изменить'));
    await t.enterText(field('name'), 'Карандаш HB');
    await tap(t, find.text('Сохранить'));
    expect(find.text('Карандаш HB'), findsOneWidget);
    expect(find.text('Карандаш'), findsNothing);
    expect(api.rows.singleWhere((i) => i.id == pencil.id).name, 'Карандаш HB');
  });

  testWidgets('TC07 — поиск по части названия и пустой результат', (t) async {
    await catalog(t, api);
    await t.enterText(field('search'), 'АНДА');
    await t.pumpAndSettle();
    expect(find.text('Карандаш'), findsOneWidget);
    expect(find.text('Бумага'), findsNothing);
    await t.enterText(field('search'), 'нет такого товара');
    await t.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('TC08 — переход в профиль и выход', (t) async {
    await catalog(t, api);
    await tap(t, find.text('Профиль'));
    expect(find.text('Администратор'), findsOneWidget);
    await tap(t, find.text('Выйти'));
    expect(api.username, isNull);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('TC09 — повторный запуск с сохранённой записью', (t) async {
    await catalog(t, api);
    await create(t);
    await t.pumpWidget(const SizedBox.shrink());
    final nextSession = TestWarehouse(api.rows);
    await catalog(t, nextSession);
    expect(find.text('Маркер'), findsOneWidget);
  });

  testWidgets('TC10 — ошибка сети и повторная загрузка', (t) async {
    api.online = false;
    await login(t, api);
    expect(find.text('Нет соединения'), findsOneWidget);
    api.online = true;
    await tap(t, find.text('Повторить'));
    expect(find.text('Нет соединения'), findsNothing);
    expect(find.text('5 шт.'), findsOneWidget);
  });
}
