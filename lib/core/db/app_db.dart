import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDb {
  static const fileName = 'controle_financeiro.db';
  static Database? _db;

  static Future<String> get filePath async =>
      kIsWeb ? fileName : join(await getDatabasesPath(), fileName);

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = await filePath;

    return openDatabase(
      path,
      version: 16,
      // ✅ MUITO IMPORTANTE: habilita FK (para ON DELETE CASCADE funcionar)
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      onCreate: (db, version) async {
        // ------------------------------
        // transactions (já com v2)
        // ------------------------------
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            is_income INTEGER NOT NULL,
            date_ms INTEGER NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            receipt_image_path TEXT,

            -- ✅ NOVOS CAMPOS (pagamento / crédito)
            payment_method TEXT NOT NULL DEFAULT 'pix',
            credit_card_id INTEGER,
            installments INTEGER,
            account_id INTEGER
          )
        ''');

        // ------------------------------
        // receipt_items (itens extraídos de cupom / nota)
        // ------------------------------
        await db.execute('''
  CREATE TABLE receipt_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tx_id INTEGER NOT NULL,
    date_ms INTEGER NOT NULL,

    raw_name TEXT NOT NULL,
    display_name TEXT,
    norm_name TEXT NOT NULL,
    price REAL NOT NULL,

    qty REAL,
    unit TEXT,
    market TEXT,
    line_total REAL,
    price_source TEXT,

    FOREIGN KEY (tx_id) REFERENCES transactions(id) ON DELETE CASCADE
  )
''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_receipt_items_norm_date ON receipt_items(norm_name, date_ms DESC)',
        );

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_receipt_items_tx ON receipt_items(tx_id)',
        );
        // ------------------------------
        // vehicles
        // ------------------------------
        await db.execute('''
          CREATE TABLE vehicles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL, -- 'car' | 'motorcycle'
            plate TEXT,
            fuel_type TEXT NOT NULL, -- 'gasolina' | 'etanol' | 'diesel'
            created_at_ms INTEGER NOT NULL
          )
        ''');

        // ------------------------------
        // fuel_logs (abastecimentos)
        // ------------------------------
        await db.execute('''
          CREATE TABLE fuel_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            vehicle_id INTEGER NOT NULL,
            date_ms INTEGER NOT NULL,
            odometer REAL NOT NULL,
            liters REAL NOT NULL,
            price_per_liter REAL NOT NULL,
            total_amount REAL NOT NULL,
            km_per_liter REAL,
            note TEXT,

            FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_fuel_logs_vehicle_date ON fuel_logs(vehicle_id, date_ms DESC)',
        );

        // ------------------------------
        // categories (categorias customizadas)
        // ------------------------------
        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE,
            icon_key TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL
          )
        ''');

        // ------------------------------
        // selected_notification_apps (apps que o usuário marcou para importar)
        // ------------------------------
        await db.execute('''
          CREATE TABLE IF NOT EXISTS selected_notification_apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package_name TEXT NOT NULL UNIQUE,
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at_ms INTEGER NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_selected_apps_enabled ON selected_notification_apps(enabled)',
        );

        // ------------------------------
        // pending_notifications (caixa de entrada de notificações)
        // ------------------------------
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pending_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            notif_key TEXT NOT NULL UNIQUE,
            package_name TEXT NOT NULL,
            title TEXT,
            text TEXT,
            posted_at_ms INTEGER NOT NULL,
            parsed_amount REAL,
            parsed_is_income INTEGER,
            parsed_method TEXT,
            suggested_category TEXT,
            reminder_at_ms INTEGER,
            status TEXT NOT NULL DEFAULT 'pending',
            imported_tx_id INTEGER
          )
        ''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pending_notif_status_date ON pending_notifications(status, posted_at_ms DESC)',
        );

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pending_notif_pkg_date ON pending_notifications(package_name, posted_at_ms DESC)',
        );

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pending_notif_reminder ON pending_notifications(status, reminder_at_ms)',
        );

        await _createIntelligenceTables(db);
        await _createRecurringExpensesTable(db);
        await _createBudgetsTable(db);
        await _createAccountsAndCardsTables(db);
        await _createSavingsGoalsTables(db);
      },

      onUpgrade: (db, oldVersion, newVersion) async {
        // ✅ v1 -> v2 (mantém extrato intacto)
        if (oldVersion < 2) {
          // 1) payment_method (NOT NULL) precisa ter DEFAULT
          await db.execute(
            "ALTER TABLE transactions ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'pix'",
          );

          // 2) Campos opcionais de crédito
          await db.execute(
            "ALTER TABLE transactions ADD COLUMN credit_card_id INTEGER",
          );

          await db.execute(
            "ALTER TABLE transactions ADD COLUMN installments INTEGER",
          );
        }

        // ✅ v2 -> v3 (novas tabelas veículos/abastecimentos)
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS vehicles (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              plate TEXT,
              fuel_type TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS fuel_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              vehicle_id INTEGER NOT NULL,
              date_ms INTEGER NOT NULL,
              odometer REAL NOT NULL,
              liters REAL NOT NULL,
              price_per_liter REAL NOT NULL,
              total_amount REAL NOT NULL,
              km_per_liter REAL,
              note TEXT,

              FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE CASCADE
            )
          ''');

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_fuel_logs_vehicle_date ON fuel_logs(vehicle_id, date_ms DESC)',
          );
        }

        // ✅ v3 -> v4 (categorias customizadas)
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE COLLATE NOCASE,
              icon_key TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL
            )
          ''');
        }

        // ✅ v4 -> v5 (itens de cupom/nota em receipt_items)
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS receipt_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              tx_id INTEGER NOT NULL,
              date_ms INTEGER NOT NULL,
              raw_name TEXT NOT NULL,
              norm_name TEXT NOT NULL,
              price REAL NOT NULL,
              qty REAL,
              unit TEXT,
              market TEXT,
              FOREIGN KEY (tx_id) REFERENCES transactions(id) ON DELETE CASCADE
            )
          ''');
        }

        // ✅ v5 -> v6 (importação por notificações)
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS selected_notification_apps (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              package_name TEXT NOT NULL UNIQUE,
              enabled INTEGER NOT NULL DEFAULT 1,
              created_at_ms INTEGER NOT NULL
            )
          ''');

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_selected_apps_enabled ON selected_notification_apps(enabled)',
          );

          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              notif_key TEXT NOT NULL UNIQUE,
              package_name TEXT NOT NULL,
              title TEXT,
              text TEXT,
              posted_at_ms INTEGER NOT NULL,
              parsed_amount REAL,
              parsed_is_income INTEGER,
              parsed_method TEXT,
              status TEXT NOT NULL DEFAULT 'pending',
              imported_tx_id INTEGER
            )
          ''');

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_pending_notif_status_date ON pending_notifications(status, posted_at_ms DESC)',
          );

          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_pending_notif_pkg_date ON pending_notifications(package_name, posted_at_ms DESC)',
          );
        }

        // v7: preserva o texto original da nota e salva o nome apresentado.
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE receipt_items ADD COLUMN display_name TEXT',
          );
          await db.execute(
            'UPDATE receipt_items SET display_name = raw_name WHERE display_name IS NULL',
          );
        }

        // v8: registra o total da linha e se o unitário veio da nota ou cálculo.
        if (oldVersion < 8) {
          await db.execute(
            'ALTER TABLE receipt_items ADD COLUMN line_total REAL',
          );
          await db.execute(
            'ALTER TABLE receipt_items ADD COLUMN price_source TEXT',
          );
        }

        // v9: caixa de entrada inteligente e lembretes de revisão.
        if (oldVersion < 9) {
          await db.execute(
            'ALTER TABLE pending_notifications ADD COLUMN suggested_category TEXT',
          );
          await db.execute(
            'ALTER TABLE pending_notifications ADD COLUMN reminder_at_ms INTEGER',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_pending_notif_reminder ON pending_notifications(status, reminder_at_ms)',
          );
        }

        // v10: aprendizado local e controle de recorrências detectadas.
        if (oldVersion < 10) {
          await _createIntelligenceTables(db);
        }
        if (oldVersion < 11) {
          await _createRecurringExpensesTable(db);
        }
        if (oldVersion < 12) {
          await _createBudgetsTable(db);
        }
        if (oldVersion < 13) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(recurring_expenses)',
          );
          final hasIconImage = columns.any(
            (column) => column['name'] == 'icon_image',
          );
          if (!hasIconImage) {
            await db.execute(
              'ALTER TABLE recurring_expenses ADD COLUMN icon_image BLOB',
            );
          }
        }
        if (oldVersion < 14) {
          final columns = await db.rawQuery(
            'PRAGMA table_info(recurring_expenses)',
          );
          final hasPaymentMethod = columns.any(
            (column) => column['name'] == 'payment_method',
          );
          if (!hasPaymentMethod) {
            await db.execute(
              "ALTER TABLE recurring_expenses ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'Pix'",
            );
          }
        }
        if (oldVersion < 15) {
          await _createAccountsAndCardsTables(db);
          final transactionColumns = await db.rawQuery(
            'PRAGMA table_info(transactions)',
          );
          if (transactionColumns.isNotEmpty &&
              !transactionColumns.any(
                (column) => column['name'] == 'account_id',
              )) {
            await db.execute(
              'ALTER TABLE transactions ADD COLUMN account_id INTEGER',
            );
          }
          final recurringColumns = await db.rawQuery(
            'PRAGMA table_info(recurring_expenses)',
          );
          if (!recurringColumns.any(
            (column) => column['name'] == 'credit_card_id',
          )) {
            await db.execute(
              'ALTER TABLE recurring_expenses ADD COLUMN credit_card_id INTEGER',
            );
          }
        }
        if (oldVersion < 16) {
          await _createSavingsGoalsTables(db);
        }
      },
    );
  }

  static Future<void> _createIntelligenceTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_learning_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        merchant_key TEXT NOT NULL UNIQUE,
        merchant_name TEXT NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        is_income INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 1,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_learning_rules_updated ON transaction_learning_rules(updated_at_ms DESC)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_preferences (
        recurrence_key TEXT PRIMARY KEY,
        ignored INTEGER NOT NULL DEFAULT 0,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createRecurringExpensesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        due_day INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        icon_image BLOB,
        payment_method TEXT NOT NULL DEFAULT 'Pix',
        credit_card_id INTEGER,
        created_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_recurring_expenses_active_due ON recurring_expenses(active, due_day)',
    );
  }

  static Future<void> _createBudgetsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS monthly_budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL UNIQUE COLLATE NOCASE,
        amount REAL NOT NULL,
        warning_percent INTEGER NOT NULL DEFAULT 80,
        active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createAccountsAndCardsTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS financial_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        initial_balance REAL NOT NULL DEFAULT 0,
        color_value INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        brand TEXT NOT NULL,
        last_four TEXT,
        limit_amount REAL NOT NULL,
        closing_day INTEGER NOT NULL,
        due_day INTEGER NOT NULL,
        account_id INTEGER,
        color_value INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (account_id) REFERENCES financial_accounts(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_credit_cards_active ON credit_cards(active, name)',
    );
  }

  static Future<void> _createSavingsGoalsTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        deadline_ms INTEGER,
        icon_key TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_goal_contributions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        goal_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        FOREIGN KEY (goal_id) REFERENCES savings_goals(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_savings_goals_completed ON savings_goals(completed, created_at_ms DESC)',
    );
  }

  /// Fecha o banco antes de uma restauração e permite reabri-lo com segurança.
  static Future<void> close() async {
    final database = _db;
    _db = null;
    if (database != null && database.isOpen) await database.close();
  }

  // ---------------------------------------------------------------------------
  // Helpers: categorias customizadas
  // ---------------------------------------------------------------------------

  /// Retorna todas as categorias cadastradas pelo usuário (tabela `categories`).
  /// Se a tabela ainda não existir (banco antigo), retorna lista vazia.
  static Future<List<Map<String, Object?>>> getCategories() async {
    final db = await instance;
    try {
      return await db.query(
        'categories',
        columns: const ['name', 'icon_key', 'created_at_ms'],
        orderBy: 'LOWER(name) ASC',
      );
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  /// Retorna apenas os nomes das categorias (em ordem alfabética).
  static Future<List<String>> getCategoryNames() async {
    final rows = await getCategories();
    return rows
        .map((r) => (r['name'] as String?)?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }
}
