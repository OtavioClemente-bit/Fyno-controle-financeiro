import 'package:controle_financeiro/core/db/app_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDb.close();
    await deleteDatabase(await AppDb.filePath);
  });

  test('v12 atualiza recorrências sem perder dados', () async {
    final path = join(await getDatabasesPath(), AppDb.fileName);
    final oldDb = await openDatabase(
      path,
      version: 12,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE recurring_expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            due_day INTEGER NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            note TEXT,
            icon_image BLOB,
            created_at_ms INTEGER NOT NULL
          )
        ''');
        await db.insert('recurring_expenses', {
          'name': 'Internet',
          'amount': 99.90,
          'category': 'Contas',
          'due_day': 10,
          'created_at_ms': 1,
        });
      },
    );
    await oldDb.close();

    final upgradedDb = await AppDb.instance;
    final columns = await upgradedDb.rawQuery(
      'PRAGMA table_info(recurring_expenses)',
    );
    final rows = await upgradedDb.query('recurring_expenses');

    expect(await upgradedDb.getVersion(), 16);
    expect(
      columns.where((column) => column['name'] == 'icon_image'),
      hasLength(1),
    );
    expect(rows.single['name'], 'Internet');
    expect(rows.single['payment_method'], 'Pix');
    expect(
      columns.where((column) => column['name'] == 'credit_card_id'),
      hasLength(1),
    );
  });
}
