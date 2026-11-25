import 'package:flutter/material.dart';

import 'components.dart';
import 'warehouse_api.dart';

class Overview extends StatelessWidget {
  const Overview({super.key, required this.items, required this.openCatalog});
  final List<Item> items;
  final VoidCallback openCatalog;

  @override
  Widget build(BuildContext context) {
    final count = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final value = items.fold<double>(
      0,
      (sum, item) => sum + item.price * item.quantity,
    );
    final low = [...items]..sort((a, b) => a.quantity.compareTo(b.quantity));
    final type = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: pine,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: lime, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Остаток на складе',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '${formatNumber(count)} шт.',
                style: type.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: lime,
                ),
              ),
              const Divider(color: Color(0xFF527268), height: 32),
              const Text(
                'Стоимость запасов',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatNumber(value)} ₸',
                style: type.titleLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          margin: EdgeInsets.zero,
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.list_alt_rounded, color: pine),
            title: const Text('Каталог товаров'),
            subtitle: Text('Наименований: ${items.length}'),
            trailing: const Icon(Icons.arrow_forward_rounded),
            onTap: openCatalog,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Наименьшие остатки',
          style: type.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (low.isEmpty) const Text('В каталоге пока нет товаров.'),
        for (final item in low.take(4))
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('Товар №${item.id}'),
            trailing: Text(
              '${formatNumber(item.quantity)} шт.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class Catalog extends StatelessWidget {
  const Catalog({
    super.key,
    required this.items,
    required this.query,
    required this.byQuantity,
    required this.onQuery,
    required this.onSort,
    required this.canModify,
    required this.onEdit,
    required this.onDelete,
  });
  final List<Item> items;
  final String query;
  final bool byQuantity;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onSort;
  final bool canModify;
  final ValueChanged<Item> onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final search = query.trim().toLowerCase();
    final filtered =
        items.where((i) => i.name.toLowerCase().contains(search)).toList()
          ..sort((a, b) {
            final q = byQuantity ? a.quantity.compareTo(b.quantity) : 0;
            if (q != 0) return q;
            final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return n == 0 ? a.id.compareTo(b.id) : n;
          });
    // One scroll surface keeps the search and results usable with the keyboard open.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 92),
      itemCount: 1 + (filtered.isEmpty ? 1 : filtered.length),
      itemBuilder: (context, index) {
        if (index == 0)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('search'),
                initialValue: query,
                onChanged: onQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Поиск по названию',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Найдено: ${filtered.length}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'Сортировка',
                    onSelected: onSort,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: false, child: Text('По названию')),
                      PopupMenuItem(value: true, child: Text('По остатку')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort, size: 19),
                          const SizedBox(width: 5),
                          Text(byQuantity ? 'По остатку' : 'По названию'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        if (filtered.isEmpty)
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Text(
              search.isEmpty ? 'Товаров пока нет' : 'Ничего не найдено',
              textAlign: TextAlign.center,
            ),
          );
        final item = filtered[index - 1];
        return Card(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
            title: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '№${item.id}  ·  ${formatNumber(item.price)} ₸  ·  ${formatNumber(item.quantity)} шт.',
              ),
            ),
            trailing: canModify
                ? PopupMenuButton<String>(
                    tooltip: 'Действия: ${item.name}',
                    onSelected: (choice) =>
                        choice == 'edit' ? onEdit(item) : onDelete(item),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Изменить')),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.api, required this.onLogout});
  final WarehouseApi api;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: CircleAvatar(
          backgroundColor: lime,
          foregroundColor: pine,
          radius: 32,
          child: const Icon(Icons.person_outline, size: 36),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        api.username ?? '',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(api.isAdmin ? 'Администратор' : 'Читатель'),
      const Divider(height: 40),
      Text(
        api.isAdmin
            ? 'Просмотр и изменение каталога товаров.'
            : 'Просмотр каталога и складских остатков.',
      ),
      const SizedBox(height: 28),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout),
        label: const Text('Выйти'),
      ),
    ],
  );
}
