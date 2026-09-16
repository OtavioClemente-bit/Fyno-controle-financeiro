import '../../../core/db/app_db.dart';
import '../models/fuel_log.dart';

class FuelLogRepository {
  Future<int> insert(FuelLog log) async {
    final db = await AppDb.instance;
    return db.insert('fuel_logs', log.toMap());
  }

  Future<int> update(FuelLog log) async {
    final db = await AppDb.instance;
    if (log.id == null) return 0;
    return db.update(
      'fuel_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await AppDb.instance;
    return db.delete('fuel_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FuelLog>> getByVehicle(int vehicleId) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'fuel_logs',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'date_ms DESC, id DESC',
    );
    return rows.map(FuelLog.fromMap).toList();
  }

  Future<FuelLog?> getLastByVehicle(int vehicleId) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'fuel_logs',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'date_ms DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FuelLog.fromMap(rows.first);
  }

  /// ✅ pega o abastecimento anterior ao `currentDate` (ideal pra calcular km/L)
  Future<FuelLog?> getPreviousLog(int vehicleId, DateTime currentDate) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'fuel_logs',
      where: 'vehicle_id = ? AND date_ms < ?',
      whereArgs: [vehicleId, currentDate.millisecondsSinceEpoch],
      orderBy: 'date_ms DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FuelLog.fromMap(rows.first);
  }

  /// ✅ fallback simples: pega o mais recente (sem filtrar por data)
  /// Útil se você não quiser passar currentDate.
  Future<FuelLog?> getPreviousLogSimple(int vehicleId) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'fuel_logs',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'date_ms DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FuelLog.fromMap(rows.first);
  }
}
