class Trip {
  const Trip(
      {required this.origin,
      required this.destination,
      required this.category,
      required this.recommendedFare,
      required this.minimumFare,
      required this.distanceKm,
      required this.durationMinutes});
  final String origin;
  final String destination;
  final String category;
  final int recommendedFare;
  final int minimumFare;
  final double distanceKm;
  final int durationMinutes;
}

class DriverOffer {
  const DriverOffer(
      {required this.name,
      required this.etaMinutes,
      required this.rating,
      required this.amount,
      required this.vehicle,
      required this.plate});
  final String name;
  final int etaMinutes;
  final double rating;
  final int amount;
  final String vehicle;
  final String plate;
}

const categories = [
  'Carro Normal',
  'Carro Comfort',
  'Moto Básica',
  'Moto Premium'
];
const seededOffers = [
  DriverOffer(
      name: 'Camilo R.',
      etaMinutes: 4,
      rating: 4.9,
      amount: 20000,
      vehicle: 'Carro Normal',
      plate: 'XYZ-123'),
  DriverOffer(
      name: 'Valentina M.',
      etaMinutes: 3,
      rating: 4.8,
      amount: 22000,
      vehicle: 'Carro Comfort',
      plate: 'IR-4821'),
  DriverOffer(
      name: 'Andrés P.',
      etaMinutes: 7,
      rating: 4.9,
      amount: 21000,
      vehicle: 'Carro Normal',
      plate: 'KLM-908'),
];

String cop(int amount) {
  final text = amount.toString();
  final groups = <String>[];
  for (var end = text.length; end > 0; end -= 3) {
    final start = end - 3 < 0 ? 0 : end - 3;
    groups.insert(0, text.substring(start, end));
  }
  return '\$${groups.join('.')} COP';
}
