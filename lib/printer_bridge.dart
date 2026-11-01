import 'package:blue_thermal_printer/blue_thermal_printer.dart'
    show BluetoothDevice;
import 'package:flutter/services.dart';

/// Thin client for the native Bluetooth printer bridge in MainActivity.kt.
///
/// Same surface the billing screen already used (isOn, getBondedDevices,
/// connect, writeBytes …) but with honest results: a write that fails
/// throws, [isConnected] reflects the real socket, and Android 12+
/// Bluetooth permission is requested before any call that needs it.
class ThermalPrinter {
  ThermalPrinter._();
  static final ThermalPrinter instance = ThermalPrinter._();

  static const MethodChannel _channel = MethodChannel('thermal_printer');

  Future<bool?> get isAvailable async =>
      await _channel.invokeMethod<bool>('isAvailable');

  Future<bool?> get isOn async => await _channel.invokeMethod<bool>('isOn');

  Future<bool?> get isConnected async =>
      await _channel.invokeMethod<bool>('isConnected');

  /// Asks for "Nearby devices" permission on Android 12+. Returns whether it
  /// is granted (always true on older Android).
  Future<bool> ensurePermission() async =>
      (await _channel.invokeMethod<bool>('ensurePermission')) ?? false;

  Future<List<BluetoothDevice>> getBondedDevices() async {
    if (!await ensurePermission()) {
      throw PlatformException(
        code: 'no_permission',
        message:
            'Bluetooth permission denied. Allow "Nearby devices" for this app in Settings.',
      );
    }
    final list =
        await _channel.invokeListMethod<Map>('getBondedDevices') ?? const [];
    return list
        .map((m) => BluetoothDevice(
            m['name']?.toString() ?? 'Unknown', m['address']?.toString()))
        .toList();
  }

  Future<bool> connect(BluetoothDevice device) async {
    if (!await ensurePermission()) {
      throw PlatformException(
        code: 'no_permission',
        message:
            'Bluetooth permission denied. Allow "Nearby devices" for this app in Settings.',
      );
    }
    return (await _channel
            .invokeMethod<bool>('connect', {'address': device.address})) ??
        false;
  }

  Future<void> disconnect() => _channel.invokeMethod('disconnect');

  /// Throws [PlatformException] if the printer is gone or the write fails.
  Future<void> writeBytes(Uint8List bytes) =>
      _channel.invokeMethod('write', {'bytes': bytes});
}
