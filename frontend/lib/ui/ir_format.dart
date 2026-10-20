String irMoney(dynamic value) {
  final amount = num.tryParse(value?.toString() ?? '') ?? 0;
  final digits = amount
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'COP $digits';
}

String irRideStatus(String? value) =>
    const {
      'searching': 'Buscando conductor',
      'requested': 'Solicitado',
      'negotiating': 'Recibiendo ofertas',
      'accepted': 'Aceptado',
      'driver_selected': 'Conductor seleccionado',
      'en_route': 'En camino',
      'arrived': 'En el punto de encuentro',
      'in_progress': 'En viaje',
      'completed': 'Completado',
      'validated': 'Validado',
      'cancelled': 'Cancelado',
    }[value] ??
    'Pendiente';
