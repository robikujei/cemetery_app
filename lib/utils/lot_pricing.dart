class LotPrice {
  const LotPrice({
    required this.type,
    required this.atNeed,
    required this.preNeed,
  });

  final String type;
  final double atNeed;
  final double preNeed;
}

const lotPriceCatalog = <LotPrice>[
  LotPrice(type: 'Super Prime A', atNeed: 40518, preNeed: 25527),
  LotPrice(type: 'Super Prime B', atNeed: 34729, preNeed: 21880),
  LotPrice(type: 'Super Prime C', atNeed: 28942, preNeed: 18234),
  LotPrice(type: 'Prime A', atNeed: 34729, preNeed: 21880),
  LotPrice(type: 'Prime B', atNeed: 28942, preNeed: 18234),
  LotPrice(type: 'Regular Lot', atNeed: 23153, preNeed: 14587),
  LotPrice(type: 'Corner Lot', atNeed: 52094, preNeed: 32819),
  LotPrice(type: 'Family Estate', atNeed: 694575, preNeed: 437583),
];

const double defaultIntermentFee = 13313;

LotPrice? lotPriceForType(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  for (final price in lotPriceCatalog) {
    if (price.type.toLowerCase() == normalized) return price;
  }
  return null;
}

double? atNeedPriceForType(String? value) => lotPriceForType(value)?.atNeed;

double? preNeedPriceForType(String? value) => lotPriceForType(value)?.preNeed;
