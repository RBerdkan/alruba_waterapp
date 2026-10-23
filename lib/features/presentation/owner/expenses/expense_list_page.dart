// lib/screens/expenses_screen.dart

import 'package:alruba_waterapp/features/presentation/owner/products/add_product_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/formatters/formatter_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'package:alruba_waterapp/models/expense.dart';
import 'package:alruba_waterapp/providers/expense_provider.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _selectedTypeFilter;

  // Single formatter instance
  final _currencyFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'LBP ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expenseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نظرة عامة على المصاريف'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            tooltip: 'إزالة الفلتر',
            onPressed: _selectedTypeFilter == null
                ? null
                : () => setState(() => _selectedTypeFilter = null),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(expenseProvider.notifier).loadExpenses(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_expense_fab',
        onPressed: () => _showAddExpenseForm(context),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(expenseProvider.notifier).loadExpenses(),
        child: _buildBody(context, state, theme),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ExpenseState state, ThemeData theme) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.read(expenseProvider.notifier).loadExpenses(),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.expenses.isEmpty) {
      return const Text('لم يتم العثور على مصاريف');
    }

    final filtered = _selectedTypeFilter == null
        ? state.expenses
        : state.expenses
            .where((e) => e.type == _selectedTypeFilter)
            .toList(growable: false);

    final grouped = groupBy(
      filtered,
      (Expense e) => DateTime(e.date.year, e.date.month),
    );

    final months = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _buildTypeFilterChips(theme),
        ...months.expand((month) => [
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  minHeight: 48,
                  maxHeight: 48,
                  child: _MonthHeader(
                    month: month,
                    expenses: grouped[month]!,
                    currencyFormat: _currencyFormat,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final exp = grouped[month]![index];
                    return _ExpenseItem(
                      expense: exp,
                      currencyFormat: _currencyFormat,
                      onTap: () => _showEditExpenseForm(context, exp),
                      onDelete: () => _deleteExpense(exp),
                    );
                  },
                  childCount: grouped[month]!.length,
                ),
              ),
            ]),
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).padding.bottom + 80,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterChips(ThemeData theme) {
    final asyncTypes = ref.watch(expenseTypesProvider);

    return SliverToBoxAdapter(
      child: asyncTypes.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (types) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('كل الأنواع'),
                selected: _selectedTypeFilter == null,
                onSelected: (_) => setState(() => _selectedTypeFilter = null),
              ),
              ...types.map((t) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(toBeginningOfSentenceCase(t) ?? t),
                      selected: _selectedTypeFilter == t,
                      onSelected: (_) =>
                          setState(() => _selectedTypeFilter = t),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddExpenseForm(BuildContext context) {
    _openExpenseForm(context, null);
  }

  void _showEditExpenseForm(BuildContext context, Expense exp) {
    _openExpenseForm(context, exp);
  }

  Future<void> _openExpenseForm(BuildContext context, Expense? expense) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: _ExpenseForm(
          expense: expense,
          currencyFormat: _currencyFormat,
          onSave: (exp) async {
            if (expense == null) {
              await ref.read(expenseProvider.notifier).addExpense(exp);
            } else {
              await ref.read(expenseProvider.notifier).updateExpense(exp);
            }
            ref.invalidate(expenseTypesProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  Future<void> _deleteExpense(Expense exp) async {
    // Optimistically remove from UI
    final prevExpenses = ref.read(expenseProvider).expenses;
    final newExpenses = List<Expense>.from(prevExpenses)
      ..removeWhere((e) => e.id == exp.id);
    ref.read(expenseProvider.notifier).state = ref
        .read(expenseProvider.notifier)
        .state
        .copyWith(expenses: newExpenses);
    // Call backend delete
    await ref.read(expenseProvider.notifier).deleteExpense(exp.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Expense deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await ref.read(expenseProvider.notifier).addExpense(exp);
            },
          ),
        ),
      );
    }
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _StickyHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.expenses,
    required this.currencyFormat,
  });

  final DateTime month;
  final List<Expense> expenses;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalAmount = expenses.fold<double>(0, (sum, e) => sum + e.amount);

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(DateFormat('MMMM y', 'ar').format(month),
              style: theme.textTheme.titleMedium),
          const Spacer(),
          Chip(
            label: Text(currencyFormat.format(totalAmount)),
            backgroundColor: Colors.green.shade100,
            avatar: const Icon(Icons.summarize, size: 18, color: Colors.green),
          ),
        ],
      ),
    );
  }
}

class _ExpenseItem extends StatelessWidget {
  const _ExpenseItem({
    required this.expense,
    required this.currencyFormat,
    required this.onTap,
    required this.onDelete,
  });

  final Expense expense;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: ListTile(
          title: Text(toBeginningOfSentenceCase(expense.type) ?? expense.type),
          subtitle: Text(
            [
              DateFormat.yMMMd('ar').format(expense.date),
              if (expense.description?.isNotEmpty ?? false) expense.description!
            ].join(' • '),
          ),
          trailing: Text(
            currencyFormat.format(expense.amount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    this.expense,
    required this.currencyFormat,
    required this.onSave,
  });

  final Expense? expense;
  final NumberFormat currencyFormat;
  final void Function(Expense) onSave;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _key = GlobalKey<FormState>();

  late TextEditingController _amountCtrl;
  late TextEditingController _descCtrl;
  late DateTime _date;
  String? _type;
  bool _addingNewType = false;
  final _newTypeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _type = widget.expense?.type;
    _amountCtrl = TextEditingController(
        text: widget.expense?.amount.toStringAsFixed(2) ?? '');
    _descCtrl = TextEditingController(text: widget.expense?.description ?? '');
    _date = widget.expense?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _newTypeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.expense == null ? 'Add Expense' : 'Edit Expense',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Consumer(builder: (context, ref, _) {
            final asyncTypes = ref.watch(expenseTypesProvider);
            return asyncTypes.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (types) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: 'النوع',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...types.map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(toBeginningOfSentenceCase(t) ?? t),
                          )),
                      const DropdownMenuItem(
                        value: '_add_new_',
                        child: Text('نوع جديد...'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == '_add_new_') {
                        setState(() {
                          _addingNewType = true;
                          _type = null;
                        });
                      } else {
                        setState(() {
                          _addingNewType = false;
                          _type = val;
                        });
                      }
                    },
                    validator: (_) {
                      if (!_addingNewType &&
                          (_type == null || _type!.isEmpty)) {
                        return 'Select a type';
                      }
                      return null;
                    },
                  ),
                  if (_addingNewType)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        controller: _newTypeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'نوع جديد',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (_addingNewType &&
                              (v == null || v.trim().isEmpty)) {
                            return 'Enter a type';
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'المبلغ',
              border: OutlineInputBorder(),
              prefixText: 'LBP ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsFormatter()],
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              final cleaned = toNumericString(v);
              final d = double.tryParse(cleaned);
              if (d == null || d <= 0) return 'Invalid';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'الوصف (اختياري)',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: Colors.grey.shade200,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text('Date: ${DateFormat.yMMMd('ar').format(_date)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: Text(widget.expense == null ? 'Add Expense' : 'Save'),
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;

    final typeStr = _addingNewType ? _newTypeCtrl.text.trim() : _type!;
    final raw = toNumericString(_amountCtrl.text);
    final amount = double.parse(raw);

    widget.onSave(
      Expense(
        id: widget.expense?.id ?? '',
        type: typeStr,
        amount: amount,
        description: _descCtrl.text.trim(),
        date: _date,
        isRecurring: widget.expense?.isRecurring ?? false,
        recurrenceEnd: widget.expense?.recurrenceEnd,
        createdAt: widget.expense?.createdAt ?? DateTime.now(),
      ),
    );
  }
}
