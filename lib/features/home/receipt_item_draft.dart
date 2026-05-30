class ReceiptItemDraft {
  String name;
  double price;
  double? qty;
  String? unit;

  ReceiptItemDraft({
    required this.name,
    required this.price,
    this.qty,
    this.unit,
  });

  ReceiptItemDraft copy() => ReceiptItemDraft(
        name: name,
        price: price,
        qty: qty,
        unit: unit,
      );
}
