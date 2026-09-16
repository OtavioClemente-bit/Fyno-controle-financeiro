class FuelLog {
  final int? id;
  final int vehicleId;

  final DateTime date;
  final double odometer; // km atual
  final double liters;
  final double pricePerLiter;
  final double totalAmount;

  final double? kmPerLiter; // calculado (opcional)
  final String? note;

  const FuelLog({
    this.id,
    required this.vehicleId,
    required this.date,
    required this.odometer,
    required this.liters,
    required this.pricePerLiter,
    required this.totalAmount,
    this.kmPerLiter,
    this.note,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'date_ms': date.millisecondsSinceEpoch,
      'odometer': odometer,
      'liters': liters,
      'price_per_liter': pricePerLiter,
      'total_amount': totalAmount,
      'km_per_liter': kmPerLiter,
      'note': note,
    };
  }

  factory FuelLog.fromMap(Map<String, Object?> map) {
    return FuelLog(
      id: map['id'] as int?,
      vehicleId: (map['vehicle_id'] as num).toInt(),
      date: DateTime.fromMillisecondsSinceEpoch(
        (map['date_ms'] as num).toInt(),
      ),
      odometer: (map['odometer'] as num).toDouble(),
      liters: (map['liters'] as num).toDouble(),
      pricePerLiter: (map['price_per_liter'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      kmPerLiter: map['km_per_liter'] == null
          ? null
          : (map['km_per_liter'] as num).toDouble(),
      note: map['note'] as String?,
    );
  }

  FuelLog copyWith({
    int? id,
    int? vehicleId,
    DateTime? date,
    double? odometer,
    double? liters,
    double? pricePerLiter,
    double? totalAmount,
    double? kmPerLiter,
    String? note,
  }) {
    return FuelLog(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      date: date ?? this.date,
      odometer: odometer ?? this.odometer,
      liters: liters ?? this.liters,
      pricePerLiter: pricePerLiter ?? this.pricePerLiter,
      totalAmount: totalAmount ?? this.totalAmount,
      kmPerLiter: kmPerLiter ?? this.kmPerLiter,
      note: note ?? this.note,
    );
  }
}
