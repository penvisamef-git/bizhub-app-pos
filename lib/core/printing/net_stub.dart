// The web can't open a raw connection to a printer (the app on a phone / tablet can).
Future<void> sendToNetwork(String address, List<int> bytes) async => throw UnsupportedError('network printing needs the app');
