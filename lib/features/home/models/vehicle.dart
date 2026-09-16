class Vehicle {
  final int? id;
  final String name; // Ex: "Carro", "Moto", "HB20", "CG 160"
  final String type; // 'car' | 'motorcycle'
  final String? plate;
  final String fuelType; // 'gasolina' | 'etanol' | 'diesel'
  final DateTime createdAt;

  const Vehicle({
    this.id,
    required this.name,
    required this.type,
    this.plate,
    required this.fuelType,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'plate': plate,
      'fuel_type': fuelType,
      'created_at_ms': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Vehicle.fromMap(Map<String, Object?> map) {
    return Vehicle(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      plate: map['plate'] as String?,
      fuelType: map['fuel_type'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at_ms'] as num).toInt(),
      ),
    );
  }

  Vehicle copyWith({
    int? id,
    String? name,
    String? type,
    String? plate,
    String? fuelType,
    DateTime? createdAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      plate: plate ?? this.plate,
      fuelType: fuelType ?? this.fuelType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
