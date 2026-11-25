import 'package:flutter/material.dart';

import 'components.dart';
import 'editor.dart';
import 'inventory_views.dart';
import 'warehouse_api.dart';

void main() => runApp(WarehouseApp(api: WarehouseApi(defaultApiUrl())));

class WarehouseApp extends StatelessWidget {
  const WarehouseApp({super.key, required this.api});
  final WarehouseApi api;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: pine,
    ).copyWith(primary: pine, secondaryContainer: lime, surface: canvas);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Склад',
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: canvas,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: lime,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      home: _Session(api: api),
    );
  }
}

class _Session extends StatefulWidget {
  const _Session({required this.api});
  final WarehouseApi api;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  bool signedIn = false;

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return _Login(
        api: widget.api,
        onSuccess: () => setState(() => signedIn = true),
      );
    }
    return _Workspace(
      api: widget.api,
      onLogout: () {
        widget.api.logout();
        setState(() => signedIn = false);
      },
    );
  }
}

class _Login extends StatefulWidget {
  const _Login({required this.api, required this.onSuccess});
  final WarehouseApi api;
  final VoidCallback onSuccess;
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool pending = false;
  String? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (pending || !form.currentState!.validate()) return;
    setState(() {
      pending = true;
      error = null;
    });
    try {
      await widget.api.login(username.text.trim(), password.text);
      if (mounted) widget.onSuccess();
    } on WarehouseApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: WarehouseMark(size: 58),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Склад',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: pine,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Вход в систему учёта товаров'),
                  const SizedBox(height: 28),
                  TextFormField(
                    key: const Key('username'),
                    controller: username,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Логин'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Введите логин' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('password'),
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onFieldSubmitted: (_) => signIn(),
                    decoration: const InputDecoration(labelText: 'Пароль'),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Введите пароль' : null,
                  ),
                  if (error != null) ErrorLine(message: error!),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: pending ? null : signIn,
                    child: Text(pending ? 'Вход…' : 'Войти'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.api, required this.onLogout});
  final WarehouseApi api;
  final VoidCallback onLogout;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  int tab = 0;
  List<Item> items = [];
  bool loaded = false;
  bool loading = false;
  bool modifying = false;
  String? error;
  String query = '';
  bool byQuantity = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.api.listItems();
      if (mounted)
        setState(() {
          items = data;
          loaded = true;
        });
    } on WarehouseApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> edit([Item? existing]) async {
    if (loading || modifying) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemEditor(api: widget.api, item: existing),
      ),
    );
    if (mounted && saved == true) {
      notice(existing == null ? 'Товар добавлен' : 'Товар обновлён');
      await refresh();
    }
  }

  Future<void> delete(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: Text('«${item.name}» и его складские операции будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => modifying = true);
    try {
      await widget.api.deleteItem(item.id);
      if (mounted) {
        notice('Товар удалён');
        await refresh();
      }
    } on WarehouseApiException catch (e) {
      if (mounted) notice(e.message);
    } finally {
      if (mounted) setState(() => modifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canModify = widget.api.isAdmin && !loading && !modifying;
    const titles = ['Обзор', 'Товары', 'Профиль'];
    Widget body;
    if (tab == 2) {
      body = ProfileView(api: widget.api, onLogout: widget.onLogout);
    } else if (loading && !loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Column(
        children: [
          if (loading || modifying) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: ErrorLine(message: error!)),
                  TextButton(
                    onPressed: loading ? null : refresh,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          if (loaded)
            Expanded(
              child: tab == 0
                  ? Overview(
                      items: items,
                      openCatalog: () => setState(() => tab = 1),
                    )
                  : Catalog(
                      items: items,
                      query: query,
                      byQuantity: byQuantity,
                      onQuery: (value) => setState(() => query = value),
                      onSort: (value) => setState(() => byQuantity = value),
                      canModify: canModify,
                      onEdit: edit,
                      onDelete: delete,
                    ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: WarehouseMark(size: 36)),
        title: Text(
          titles[tab],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (tab != 2)
            IconButton(
              onPressed: loading || modifying ? null : refresh,
              tooltip: 'Обновить остатки',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: body,
          ),
        ),
      ),
      floatingActionButton: tab == 1 && canModify && loaded
          ? FloatingActionButton.extended(
              onPressed: () => edit(),
              foregroundColor: pine,
              backgroundColor: lime,
              label: const Text('Добавить товар'),
              icon: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Обзор',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Товары',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
