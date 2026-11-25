import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String defaultApiUrl() {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  return kIsWeb ? Uri.base.origin : 'http://10.0.2.2:8000';
}

class WarehouseApiException implements Exception {
  const WarehouseApiException(this.message);
  final String message;
}

class ItemInput {
  const ItemInput({
    required this.name,
    required this.price,
    required this.quantity,
    required this.categoryId,
    required this.supplierId,
  });
  final String name;
  final double price;
  final int quantity, categoryId, supplierId;
  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'quantity': quantity,
    'category_id': categoryId,
    'supplier_id': supplierId,
  };
}

class Item extends ItemInput {
  const Item({
    required this.id,
    required super.name,
    required super.price,
    required super.quantity,
    required super.categoryId,
    required super.supplierId,
  });
  final int id;
  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'] as int,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    quantity: json['quantity'] as int,
    categoryId: json['category_id'] as int,
    supplierId: json['supplier_id'] as int,
  );
}

class CatalogEntry {
  const CatalogEntry({required this.id, required this.name});
  final int id;
  final String name;
  factory CatalogEntry.fromJson(Map<String, dynamic> json) =>
      CatalogEntry(id: json['id'], name: json['name']);
}

class CatalogReferences {
  const CatalogReferences({required this.categories, required this.suppliers});
  final List<CatalogEntry> categories, suppliers;
}

class WarehouseApi {
  WarehouseApi(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? _auth, username;
  bool get isAdmin => username == 'admin';

  Future<T> _request<T>(
    String method,
    String path,
    T Function(dynamic) parse, {
    String? credential,
    Map<String, dynamic>? data,
  }) async {
    final req = http.Request(
      method,
      Uri.parse(baseUrl.replaceFirst(RegExp(r'/$'), '') + path),
    );
    final basic = credential ?? _auth;
    if (basic != null) req.headers['Authorization'] = basic;
    if (data != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(data);
    }
    late http.Response response;
    try {
      response = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const WarehouseApiException('Сервер не ответил. Повторите запрос.');
    } on http.ClientException {
      throw const WarehouseApiException(
        'Не удалось подключиться к складу. Проверьте соединение.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 &&
          credential == null &&
          basic != null &&
          basic == _auth) {
        logout();
        throw const WarehouseApiException(
          'Доступ истёк. Выйдите из профиля и войдите снова.',
        );
      }
      final message = switch (response.statusCode) {
        401 => 'Проверьте имя и пароль.',
        403 => 'Недостаточно прав.',
        404 => 'Товар уже удалён.',
        409 => 'Данные изменились. Обновите список.',
        422 => 'Проверьте данные формы.',
        _ => 'Сервер отклонил запрос.',
      };
      throw WarehouseApiException(message);
    }
    const invalidResponse = WarehouseApiException(
      'Некорректный ответ сервера.',
    );
    try {
      final body = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
      return parse(body);
    } on FormatException {
      throw invalidResponse;
    } on TypeError {
      throw invalidResponse;
    }
  }

  Future<void> login(String user, String pass) async {
    logout();
    final credential = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    username = await _request(
      'GET',
      '/auth/me',
      (body) => (body as Map<String, dynamic>)['username'] as String,
      credential: credential,
    );
    _auth = credential;
  }

  void logout() {
    _auth = null;
    username = null;
  }

  Future<List<Item>> listItems() => _request(
    'GET',
    '/items',
    (body) => (body as List).map((row) => Item.fromJson(row)).toList(),
  );

  Future<CatalogReferences> references() => _request(
    'GET',
    '/catalog/references',
    (body) {
      final data = body as Map<String, dynamic>;
      List<CatalogEntry> rows(String key) =>
          (data[key] as List).map((row) => CatalogEntry.fromJson(row)).toList();
      return CatalogReferences(
        categories: rows('categories'),
        suppliers: rows('suppliers'),
      );
    },
  );

  Future<Item> createItem(ItemInput item) => _request(
    'POST',
    '/items',
    (body) => Item.fromJson(body),
    data: item.toJson(),
  );
  Future<Item> updateItem(int id, ItemInput item) => _request(
    'PUT',
    '/items/$id',
    (body) => Item.fromJson(body),
    data: item.toJson(),
  );
  Future<void> deleteItem(int id) =>
      _request<void>('DELETE', '/items/$id', (_) {});
}
