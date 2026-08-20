import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error getting location: $e');
      }
      return null;
    }
  }

  static Future<String> getAddressFromCoordinates(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return '${place.street}, ${place.locality}, ${place.subAdministrativeArea}, ${place.country}';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting address: $e');
      }
    }
    return 'Address not available';
  }

  static String formatLocationMessage(Position position, String? address) {
    String googleMapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';

    String message = '🚨 EMERGENCY ALERT 🚨\n\n';
    message += 'Accident detected!\n\n';
    message += '📍 Location:\n';
    message += 'Lat: ${position.latitude.toStringAsFixed(6)}\n';
    message += 'Lon: ${position.longitude.toStringAsFixed(6)}\n\n';

    if (address != null && address != 'Address not available') {
      message += 'Address: $address\n\n';
    }

    message += '🗺 View on map:\n$googleMapsLink\n\n';
    message += 'Accuracy: ${position.accuracy.toStringAsFixed(2)}m\n';
    message += 'Time: ${DateTime.now().toString().split('.')[0]}';

    return message;
  }

  static Future<String> getFullLocationMessage() async {
    Position? position = await getCurrentLocation();

    if (position == null) {
      return '🚨 EMERGENCY ALERT 🚨\n\nAccident detected!\nUnable to get precise location. Please send help!';
    }

    String? address = await getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    return formatLocationMessage(position, address);
  }

  static String getQuickLocationMessage(Position position) {
    String googleMapsLink = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    return '🚨 EMERGENCY 🚨\nAccident detected!\n📍 ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}\n🗺 $googleMapsLink';
  }
}