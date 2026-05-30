import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDb {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'controle_financeiro.db');

    return openDatabase(
      path,
      version:
          6, // ✅ v6 = importação por notificações (bancos) + (mantém v5: itens de cupom + categorias)
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
            installments INTEGER
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
    norm_name TEXT NOT NULL,
    price REAL NOT NULL,

    qty REAL,
    unit TEXT,
    market TEXT,

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
      },
    );
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
