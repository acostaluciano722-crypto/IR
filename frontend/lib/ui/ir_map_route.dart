import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Presentation helpers only: these never choose, price or request a route.
abstract final class IrMapRoute {
  static LatLng? point(dynamic latitude, dynamic longitude) {
    final lat = num.tryParse(latitude?.toString() ?? '')?.toDouble();
    final lng = num.tryParse(longitude?.toString() ?? '')?.toDouble();
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }

  static List<LatLng> points(Map<String, dynamic>? route) => [
        for (final raw in (route?['route_points'] as List?) ?? const [])
          if (raw is Map)
            if (point(raw['lat'], raw['lng']) case final LatLng position)
              position,
      ];

  static CameraUpdate overview(Iterable<LatLng> positions,
      {required Size viewport,
      required EdgeInsets obscured,
      double maxZoom = 18}) {
    final points = positions.toList(growable: false);
    assert(points.isNotEmpty);
    return CameraUpdate.newCameraPosition(cameraPosition(points,
        viewport: viewport, obscured: obscured, maxZoom: maxZoom));
  }

  /// Fits Mercator coordinates in the unobscured part of the full map widget.
  /// This avoids relying on native map padding, which the web plugin ignores.
  static CameraPosition cameraPosition(Iterable<LatLng> positions,
      {required Size viewport,
      required EdgeInsets obscured,
      double maxZoom = 18}) {
    final points = positions.toList(growable: false);
    assert(points.isNotEmpty);
    final reference = (points.first.longitude + 180) / 360;
    final world = points.map((point) {
      var x = (point.longitude + 180) / 360;
      if (x - reference > .5) x -= 1;
      if (reference - x > .5) x += 1;
      final sin = math.sin(point.latitude.clamp(-85.0, 85.0) * math.pi / 180);
      final y = .5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
      return Offset(x, y);
    }).toList(growable: false);
    var west = world.first.dx;
    var east = west;
    var north = world.first.dy;
    var south = north;
    for (final point in world.skip(1)) {
      west = math.min(west, point.dx);
      east = math.max(east, point.dx);
      north = math.min(north, point.dy);
      south = math.max(south, point.dy);
    }
    const margin = 36.0;
    final width =
        math.max(32.0, viewport.width - obscured.horizontal - margin * 2);
    final height =
        math.max(32.0, viewport.height - obscured.vertical - margin * 2);
    final scaleX = width / math.max(.0000001, east - west);
    final scaleY = height / math.max(.0000001, south - north);
    final zoom = (math.log(math.min(scaleX, scaleY) / 256) / math.ln2)
        .clamp(1.0, maxZoom);
    final scale = 256 * math.pow(2, zoom);
    final centerX =
        (west + east) / 2 + (obscured.right - obscured.left) / (2 * scale);
    final centerY =
        ((north + south) / 2 + (obscured.bottom - obscured.top) / (2 * scale))
            .clamp(0.0, 1.0);
    final longitude = ((centerX * 360) % 360) - 180;
    final mercator = math.pi * (1 - 2 * centerY);
    final latitude = math.atan((math.exp(mercator) - math.exp(-mercator)) / 2) *
        180 /
        math.pi;
    return CameraPosition(target: LatLng(latitude, longitude), zoom: zoom);
  }

  static Size viewport(BuildContext context) {
    final media = MediaQuery.of(context);
    return Size(
        math.max(1.0, media.size.width - media.padding.horizontal),
        math.max(1.0,
            media.size.height - media.padding.top - media.viewInsets.bottom));
  }

  static EdgeInsets padding(BuildContext context, double sheetExtent) {
    final height = viewport(context).height;
    // Reserve a usable map window even when the trip panel is fully expanded.
    final bottom =
        math.min(height * sheetExtent + 12, math.max(0.0, height - 160));
    return EdgeInsets.fromLTRB(12, math.min(80, height * .18), 12, bottom);
  }
}
