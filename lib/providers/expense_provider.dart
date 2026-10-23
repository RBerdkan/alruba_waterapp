import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alruba_waterapp/models/expense.dart';
import 'package:alruba_waterapp/repositories/expense_repository.dart';

/// ────────────────────────────────────────────────────────────────
/// SINGLE source of truth for the list of expense types
/// ────────────────────────────────────────────────────────────────
final expenseTypesProvider = FutureProvider<List<String>>((ref) {
  final repo = ref.watch(expenseRepositoryProvider);
  return repo.getExpenseTypes();
});

/// State‑notifier wiring for all CRUD operations on expenses
final expenseProvider =
    StateNotifierProvider<ExpenseProvider, ExpenseState>((ref) {
  return ExpenseProvider(ref.watch(expenseRepositoryProvider));
});

/*──────────────────────────────────────────────────────────────────*/

class ExpenseState {
  final List<Expense> expenses;
  final Map<String, double> totals;
  final bool isLoading;
  final String? error;

  ExpenseState({
    required this.expenses,
    required this.totals,
    this.isLoading = false,
    this.error,
  });

  ExpenseState copyWith({
    List<Expense>? expenses,
    Map<String, double>? totals,
    bool? isLoading,
    String? error,
  }) {
    return ExpenseState(
      expenses: expenses ?? this.expenses,
      totals: totals ?? this.totals,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class ExpenseProvider extends StateNotifier<ExpenseState> {
  final ExpenseRepository _repository;

  ExpenseProvider(this._repository)
      : super(
          ExpenseState(
            expenses: const [],
            totals: const {},
            isLoading: true,
          ),
        ) {
    loadExpenses();
  }

  /* --- existing load / add / update / delete logic unchanged --- */
  Future<void> loadExpenses() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final expenses = await _repository.fetchExpenses();
      final totals = _calculateTotals(expenses);
      state = state.copyWith(
        expenses: expenses,
        totals: totals,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load expenses: ${e.toString()}',
      );
    }
  }

  Map<String, double> _calculateTotals(List<Expense> expenses) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      totals.update(
        expense.type,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    return totals;
  }

  Future<void> addExpense(Expense expense) async {
    try {
      state = state.copyWith(isLoading: true);
      await _repository.addExpense(expense);
      await loadExpenses();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to add expense: ${e.toString()}',
      );
    }
  }

  Future<void> updateExpense(Expense expense) async {
    try {
      await _repository.updateExpense(expense);
      await loadExpenses();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      print('[DEBUG] Attempting to delete expense with id: $id');
      await _repository.deleteExpense(id);
      print('[DEBUG] Successfully deleted expense with id: $id');
      await loadExpenses();
    } catch (e) {
      print('[DEBUG][ERROR] Failed to delete expense with id: $id. Error: $e');
      state =
          state.copyWith(error: 'Failed to delete expense: ${e.toString()}');
    }
  }
}
