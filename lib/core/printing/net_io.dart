import 'dart:io';

// Send raw bytes to a network (Wi-Fi / LAN) receipt printer: ESC/POS on TCP port 9100.
Future<void> sendToNetwork(String address, List<int> bytes) async {
  final parts = address.trim().split(':');
  final host = parts.first;
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
  final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
  try {
    s.add(bytes);
    await s.flush();
  } finally {
    await s.close();
  }
}
