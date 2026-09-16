import '../../../core/db/app_db.dart';
import '../models/vehicle.dart';

class VehicleRepository {
  Future<int> insert(Vehicle v) async {
    final db = await AppDb.instance;
    return db.insert('vehicles', v.toMap());
  }

  Future<List<Vehicle>> getAll() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'vehicles',
      orderBy: 'created_at_ms DESC, id DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await AppDb.instance;
    return db.delete('vehicles', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> update(Vehicle v) async {
    final db = await AppDb.instance;
    if (v.id == null) return 0;
    return db.update('vehicles', v.toMap(), where: 'id = ?', whereArgs: [v.id]);
  }
}
