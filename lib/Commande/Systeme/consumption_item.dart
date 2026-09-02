enum CuttingItemType {
  glass,
  profileFrame,
  profileSash,
  shutter,
  accessory,
  batmo,
  parclose,
}

class CuttingItem {
  final String name;
  final String description;
  final double width;
  final double height;
  final int quantity;
  final CuttingItemType type;
  final bool isMissing;
  final double price;

  const CuttingItem({
    required this.name,
    required this.description,
    required this.width,
    required this.height,
    required this.quantity,
    required this.type,
    this.isMissing = true,
    this.price = 0.0,
  });

  double get totalPrice => price * quantity;
}
