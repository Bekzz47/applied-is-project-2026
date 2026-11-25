import 'package:flutter/material.dart';

import 'components.dart';
import 'warehouse_api.dart';

class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, required this.api, this.item});
  final WarehouseApi api;
  final Item? item;

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.item?.name);
  late final price = TextEditingController(text: widget.item?.price.toString());
  late final quantity = TextEditingController(
    text: widget.item?.quantity.toString(),
  );
  CatalogReferences? refs;
  int? category, supplier;
  String? error;
  bool loading = false, saving = false;

  @override
  void initState() {
    super.initState();
    loadReferences();
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> loadReferences() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.references();
      if (mounted)
        setState(() {
          refs = result;
          category = widget.item?.categoryId;
          supplier = widget.item?.supplierId;
          if (category == null && result.categories.length == 1) {
            category = result.categories.single.id;
          }
          if (supplier == null && result.suppliers.length == 1) {
            supplier = result.suppliers.single.id;
          }
        });
    } on WarehouseApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double? readPrice(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final input = ItemInput(
      name: name.text.trim(),
      price: readPrice(price.text)!,
      quantity: int.parse(quantity.text.trim()),
      categoryId: category!,
      supplierId: supplier!,
    );
    final item = widget.item;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (item == null) {
        await widget.api.createItem(input);
      } else {
        await widget.api.updateItem(item.id, input);
      }
      if (mounted) Navigator.pop(context, true);
    } on WarehouseApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget selector(
    String key,
    String label,
    List<CatalogEntry> entries,
    int? value,
    ValueChanged<int?> onChanged,
  ) => DropdownButtonFormField<int>(
    key: Key(key),
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: entries
        .map(
          (e) => DropdownMenuItem(
            value: e.id,
            child: Text(e.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: saving ? null : onChanged,
    validator: (v) => v == null ? 'Выберите значение' : null,
  );

  @override
  Widget build(BuildContext context) {
    final references = refs;
    late final Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (references == null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ErrorLine(message: error ?? 'Справочники недоступны'),
          TextButton(onPressed: loadReferences, child: const Text('Повторить')),
        ],
      );
    } else if (references.categories.isEmpty || references.suppliers.isEmpty) {
      content = const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Для добавления товаров заполните справочники категорий и поставщиков.',
        ),
      );
    } else {
      content = Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            TextFormField(
              key: const Key('name'),
              controller: name,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Название'),
              textInputAction: TextInputAction.next,
              validator: (v) {
                final length = (v ?? '').trim().length;
                if (length == 0) return 'Введите название';
                if (length > 200)
                  return 'Название должно быть не длиннее 200 символов';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('price'),
              controller: price,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Цена, ₸'),
              validator: (v) {
                final n = readPrice(v ?? '');
                return n == null || !n.isFinite || n < 0
                    ? 'Введите неотрицательную цену'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('quantity'),
              controller: quantity,
              enabled: !saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Количество, шт.'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 0
                    ? 'Введите целое число от нуля'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            selector(
              'category',
              'Категория',
              references.categories,
              category,
              (v) => category = v,
            ),
            const SizedBox(height: 16),
            selector(
              'supplier',
              'Поставщик',
              references.suppliers,
              supplier,
              (v) => supplier = v,
            ),
            if (error != null) ErrorLine(message: error!),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Сохранение…' : 'Сохранить'),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.item == null ? 'Новый товар' : 'Изменить товар'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
