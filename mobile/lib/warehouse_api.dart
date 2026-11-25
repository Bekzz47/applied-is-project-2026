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

  Future<dynamic> _request(
    String method,
    String path, {
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
    return response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> login(String user, String pass) async {
    logout();
    final credential = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    final identity = await _request('GET', '/auth/me', credential: credential);
    username = identity['username'] as String;
    _auth = credential;
  }

  void logout() {
    _auth = null;
    username = null;
  }

  Future<List<Item>> listItems() async =>
      (await _request('GET', '/items') as List)
          .map((row) => Item.fromJson(row))
          .toList();
  Future<CatalogReferences> references() async {
    final data = await _request('GET', '/catalog/references');
    List<CatalogEntry> rows(String key) =>
        (data[key] as List).map((row) => CatalogEntry.fromJson(row)).toList();
    return CatalogReferences(
      categories: rows('categories'),
      suppliers: rows('suppliers'),
    );
  }

  Future<Item> createItem(ItemInput item) async =>
      Item.fromJson(await _request('POST', '/items', data: item.toJson()));
  Future<Item> updateItem(int id, ItemInput item) async =>
      Item.fromJson(await _request('PUT', '/items/$id', data: item.toJson()));
  Future<void> deleteItem(int id) async {
    await _request('DELETE', '/items/$id');
  }
}
