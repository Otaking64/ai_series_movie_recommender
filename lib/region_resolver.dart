import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class RegionResolutionResult {
  const RegionResolutionResult({
    required this.countryCode,
    required this.source,
  });

  final String countryCode;
  final String source;
}

class RegionResolver {
  Future<RegionResolutionResult> resolve({
    required bool useLocation,
  }) async {
    if (useLocation) {
      final locationResult = await _tryResolveFromLocation();
      if (locationResult != null) {
        return locationResult;
      }
    }

    return _resolveFromLocale();
  }

  Future<RegionResolutionResult?> _tryResolveFromLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw TimeoutException('location timeout'),
        );
      } catch (_) {
        // Try last known position if live fix fails.
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return null;
      }

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('placemark timeout'),
      );
      if (placemarks.isEmpty) {
        return null;
      }

      final countryCode = placemarks.first.isoCountryCode;
      if (countryCode == null || countryCode.trim().isEmpty) {
        return null;
      }

      return RegionResolutionResult(
        countryCode: countryCode.toUpperCase(),
        source: 'location',
      );
    } catch (_) {
      return null;
    }
  }

  RegionResolutionResult _resolveFromLocale() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final countryCode = _countryCodeFromLocale(locale) ?? 'US';
    return RegionResolutionResult(
      countryCode: countryCode,
      source: 'locale',
    );
  }

  String? _countryCodeFromLocale(Locale locale) {
    final code = locale.countryCode;
    if (code != null && code.trim().isNotEmpty) {
      return code.toUpperCase();
    }

    if (Platform.localeName.contains('_')) {
      final parts = Platform.localeName.split('_');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        return parts[1].toUpperCase();
      }
    }

    return null;
  }
}
