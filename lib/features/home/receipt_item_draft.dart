enum ProductNameSource { receipt, local, ai, manual }

enum ReceiptPriceSource { providedUnit, calculatedFromTotal, manual }

class ReceiptItemDraft {
  String name;
  final String originalName;
  ProductNameSource nameSource;
  double price;
  double? qty;
  String? unit;
  double? lineTotal;
  ReceiptPriceSource priceSource;

  ReceiptItemDraft({
    required this.name,
    String? originalName,
    this.nameSource = ProductNameSource.receipt,
    required this.price,
    this.qty,
    this.unit,
    this.lineTotal,
    this.priceSource = ReceiptPriceSource.providedUnit,
  }) : originalName = _resolveOriginalName(originalName, name);

  factory ReceiptItemDraft.fromLineTotal({
    required String name,
    required double total,
    double? qty,
    String? unit,
    String? originalName,
  }) {
    final safeQty = _validQty(qty);
    return ReceiptItemDraft(
      name: name,
      originalName: originalName,
      price: _roundMoney(total / safeQty),
      qty: safeQty,
      unit: unit,
      lineTotal: _roundMoney(total),
      priceSource: ReceiptPriceSource.calculatedFromTotal,
    );
  }

  factory ReceiptItemDraft.fromUnitPrice({
    required String name,
    required double unitPrice,
    double? qty,
    String? unit,
    double? lineTotal,
    String? originalName,
  }) {
    final safeQty = _validQty(qty);
    return ReceiptItemDraft(
      name: name,
      originalName: originalName,
      price: _roundMoney(unitPrice),
      qty: safeQty,
      unit: unit,
      lineTotal: lineTotal == null
          ? _roundMoney(unitPrice * safeQty)
          : _roundMoney(lineTotal),
      priceSource: ReceiptPriceSource.providedUnit,
    );
  }

  bool get hasRenamedProduct =>
      originalName.trim().toLowerCase() != name.trim().toLowerCase();

  void restoreOriginalName() {
    name = originalName;
    nameSource = ProductNameSource.receipt;
  }

  double get effectiveQty => _validQty(qty);

  double get effectiveLineTotal =>
      lineTotal ?? _roundMoney(price * effectiveQty);

  bool get wasUnitPriceCalculated =>
      priceSource == ReceiptPriceSource.calculatedFromTotal;

  void setUnitPrice(double value) {
    price = value < 0 ? 0 : value;
    priceSource = ReceiptPriceSource.manual;
    lineTotal = _roundMoney(price * effectiveQty);
  }

  void setQuantity(double? value) {
    qty = _validQty(value);
    if (wasUnitPriceCalculated && lineTotal != null) {
      price = _roundMoney(lineTotal! / effectiveQty);
    } else {
      lineTotal = _roundMoney(price * effectiveQty);
    }
  }

  ReceiptItemDraft copy() => ReceiptItemDraft(
    name: name,
    originalName: originalName,
    nameSource: nameSource,
    price: price,
    qty: qty,
    unit: unit,
    lineTotal: lineTotal,
    priceSource: priceSource,
  );

  static double _validQty(double? value) {
    if (value == null || !value.isFinite || value <= 0) return 1;
    return value;
  }

  static double _roundMoney(double value) =>
      (value * 100).roundToDouble() / 100;

  static String _resolveOriginalName(String? originalName, String name) {
    final original = originalName?.trim() ?? '';
    return original.isEmpty ? name.trim() : original;
  }
}
