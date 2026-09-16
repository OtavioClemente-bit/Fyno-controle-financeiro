import 'package:flutter/material.dart';

import 'package:controle_financeiro/features/home/repositories/category_repository.dart';
import 'package:controle_financeiro/features/home/models/category_item.dart';
import 'package:controle_financeiro/shared/categories/category_icons.dart';
import 'package:controle_financeiro/shared/widgets/adaptive_pair.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final CategoryRepository _repo = CategoryRepository();

  bool _loading = true;
  List<CategoryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _repo.listAll();
      if (!mounted) return;
      setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({CategoryItem? item}) async {
    final res = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditorSheet(item: item),
    );
    if (res == null) return;

    try {
      if (item == null) {
        await _repo.create(name: res.name, iconKey: res.iconKey);
      } else {
        await _repo.update(id: item.id!, name: res.name, iconKey: res.iconKey);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  Future<void> _delete(CategoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir categoria'),
        content: Text('Tem certeza que deseja excluir "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _repo.delete(item.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível excluir: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias'),
        actions: [
          IconButton(
            tooltip: 'Nova categoria',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.category_outlined, size: 48),
                    const SizedBox(height: 10),
                    const Text('Nenhuma categoria criada ainda.'),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('Criar categoria'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = _items[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(CategoryIcons.of(c.iconKey)),
                    ),
                    title: Text(c.name),
                    subtitle: Text('Ícone: ${c.iconKey}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => _openEditor(item: c),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          onPressed: () => _delete(c),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: compact
          ? FloatingActionButton(
              onPressed: () => _openEditor(),
              tooltip: 'Nova categoria',
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nova categoria'),
            ),
    );
  }
}

class _CategoryEditorResult {
  final String name;
  final String iconKey;

  const _CategoryEditorResult({required this.name, required this.iconKey});
}

class _CategoryEditorSheet extends StatefulWidget {
  final CategoryItem? item;
  const _CategoryEditorSheet({this.item});

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  late String _iconKey;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.item?.name ?? '';
    _iconKey = widget.item?.iconKey ?? 'shopping_cart';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _CategoryEditorResult(
        name: _nameCtrl.text.trim(),
        iconKey: CategoryIcons.normalizeKey(_iconKey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item == null ? 'Nova categoria' : 'Editar categoria',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex: Mercado, Farmácia, Lazer...',
                prefixIcon: Icon(Icons.category),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Informe um nome';
                if (s.length < 2) return 'Nome muito curto';
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Ícone:'),
              Chip(
                avatar: Icon(CategoryIcons.of(_iconKey)),
                label: Text(_iconKey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 58).floor().clamp(4, 7);
                return GridView.builder(
                  itemCount: CategoryIcons.keys().length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 52,
                  ),
                  itemBuilder: (_, i) {
                    final key = CategoryIcons.keys()[i];
                    final selected = key == _iconKey;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _iconKey = key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor,
                            width: selected ? 2 : 1,
                          ),
                          color: selected
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.08)
                              : null,
                        ),
                        child: Icon(CategoryIcons.of(key)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          AdaptivePair(
            first: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            second: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
          ),
        ],
      ),
    );
  }
}
