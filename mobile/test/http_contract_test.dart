import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warehouse_mobile/warehouse_api.dart';

void main() {
  test('Login verifies the server identity and logout clears the credentials', () async {
    int count = 0;
    final api = WarehouseApi('http://localhost', client: MockClient((req) async {
      count++;
      if (req.url.path == '/auth/me') {
        expect(req.headers['Authorization'], startsWith('Basic '));
        return http.Response('{"username":"admin"}', 200);
      }
      expect(req.url.path, '/items');
      if (count == 2) {
        expect(req.headers['Authorization'], isNotNull);
      } else {
        expect(req.headers['Authorization'], isNull);
      }
      return http.Response('[]', 200);
    }));
    await api.login('admin', 'temporary-test-value');
    expect(api.isAdmin, isTrue);
    await api.listItems();
    api.logout();
    expect(api.username, isNull);
    await api.listItems();
    expect(count, 3);
  });

  test('Errors from the server do not expose response body to the user', () async {
    final api = WarehouseApi('http://localhost', client: MockClient(
      (_) async => http.Response('internal implementation details', 500),
    ));
    await expectLater(api.listItems(), throwsA(isA<WarehouseApiException>().having(
      (e) => e.message, 'message', isNot(contains('internal implementation details')),
    )));
  });

  test('Item creation sends a JSON object and decodes UTF-8 names and prices', () async {
    const input = ItemInput(name: 'Мышь', price: 1.5, quantity: 2, categoryId: 3, supplierId: 4);
    final api = WarehouseApi('http://localhost', client: MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/items');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['name'], 'Мышь');
      expect(body['category_id'], 3);
      return http.Response.bytes(utf8.encode(jsonEncode({...body, 'id': 10})), 201);
    }));
    final item = await api.createItem(input);
    expect(item.id, 10);
    expect(item.name, 'Мышь');
    expect(item.price, 1.5);
  });
}
