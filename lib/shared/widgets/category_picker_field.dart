import 'package:flutter/material.dart';

class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Categoria',
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String label;

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _CategoryPickerSheet(items: items, selected: value, title: label),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        isEmpty: value.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: Icon(
            enabled ? Icons.keyboard_arrow_down_rounded : Icons.lock_outline,
          ),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.items,
    required this.selected,
    required this.title,
  });

  final List<String> items;
  final String selected;
  final String title;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((item) => item.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: .72,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, 14 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecionar ${widget.title.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: false,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Pesquisar…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final selected = item == widget.selected;
                  return ListTile(
                    minTileHeight: 56,
                    title: Text(
                      item,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                    trailing: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
