import 'package:flutter/material.dart';

class IrMapLayout {
  const IrMapLayout._({
    required this.viewport,
    required this.textScale,
  });

  factory IrMapLayout.of(BuildContext context) => IrMapLayout._(
        viewport: MediaQuery.sizeOf(context),
        textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
      );

  final Size viewport;
  final double textScale;

  bool get veryShort => viewport.height < 460;
  bool get short => viewport.height < 650;
  bool get compact => viewport.width < 600;
  bool get largeText => textScale > 1.3;

  double get passengerMinimum => veryShort
      ? .40
      : short
          ? .32
          : .24;

  double get passengerResting => veryShort
      ? .74
      : short
          ? .62
          : .43;

  double get driverMinimum => veryShort
      ? .40
      : short
          ? .32
          : .24;

  double get driverResting => veryShort
      ? .76
      : short
          ? .66
          : .52;

  List<double> get passengerSnapSizes =>
      [passengerMinimum, passengerResting, .90, 1.0];

  List<double> get driverSnapSizes => [driverMinimum, driverResting, .90, 1.0];

  double get sheetMaxWidth {
    if (viewport.width >= 1200) return 760;
    if (viewport.width >= 720) return 680;
    return double.infinity;
  }

  double get horizontalPadding {
    if (viewport.width < 360) return 12;
    if (compact) return 16;
    return 20;
  }

  bool get showVehicleGrid =>
      viewport.width >= 720 && !largeText && viewport.height >= 480;
}
