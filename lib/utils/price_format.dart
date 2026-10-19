String formatAccessoryCardPrice(
  double basePrice,
  Iterable<double> colorPrices,
) {
  final prices = colorPrices.where((price) => price.isFinite).toList()..sort();
  if (prices.isEmpty) prices.add(basePrice);

  String format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  final lowest = prices.first;
  final highest = prices.last;
  if ((highest - lowest).abs() < 0.000001) {
    return '${format(lowest)} DA';
  }
  return '${format(lowest)} – ${format(highest)} DA';
}
