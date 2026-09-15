import 'package:flutter/foundation.dart';

import '../mock_data.dart';

class PassengerAppState extends ChangeNotifier {
  String destination = '';
  String category = categories.first;
  int proposal = 20000;
  Trip? trip;
  DriverOffer? selectedOffer;
  String status = 'draft';
  int offerCount = 0;

  List<DriverOffer> get offers => seededOffers.take(offerCount).toList();
  bool get proposalIsValid => proposal >= (trip?.minimumFare ?? 12250);

  void setDestination(String value) {
    destination = value;
    notifyListeners();
  }

  void setCategory(String value) {
    category = value;
    notifyListeners();
  }

  void setProposal(String value) {
    proposal = int.tryParse(value.replaceAll('.', '')) ?? 0;
    notifyListeners();
  }

  void prepareTrip() {
    trip = Trip(
        origin: 'Ubicación actual',
        destination: destination.trim().isEmpty
            ? 'Bocagrande, Cartagena'
            : destination.trim(),
        category: category,
        recommendedFare: 20000,
        minimumFare: 12250,
        distanceKm: 4.7,
        durationMinutes: 15);
    selectedOffer = null;
    status = 'draft';
    offerCount = 0;
    notifyListeners();
  }

  void submitRequest() {
    status = 'negotiating';
    offerCount = 1;
    notifyListeners();
  }

  void revealNextOffer() {
    if (offerCount < seededOffers.length) {
      offerCount++;
      notifyListeners();
    }
  }

  void selectOffer(DriverOffer offer) {
    selectedOffer = offer;
    status = 'driver_selected';
    notifyListeners();
  }

  void reset() {
    trip = null;
    selectedOffer = null;
    status = 'draft';
    offerCount = 0;
    notifyListeners();
  }
}
