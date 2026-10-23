import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net_stub.dart' if (dart.library.io) 'net_io.dart';

// Printing for every POS in the app.
// A receipt is a normal Flutter widget (so Khmer prints exactly like it looks); it is drawn off-screen into a picture,
// then sent to the printer:
//   network   — Wi-Fi / LAN receipt printer, ESC/POS picture on port 9100 (most kitchen printers)
//   bluetooth — a Bluetooth receipt printer paired with this phone / tablet (Android, iOS)
//   system    — the phone's own print window (AirPrint, Android printing, Save as PDF; also on the web)

enum PrinterKind { none, system, network, bluetooth }

class PrinterConf {
  final PrinterKind kind;
  final String address; // network: "192.168.1.50[:9100]" · bluetooth: MAC address
  final String name; // bluetooth: the printer's name (shown in settings)
  final int paper; // 58 | 80 mm
  const PrinterConf({this.kind = PrinterKind.none, this.address = '', this.name = '', this.paper = 80});

  bool get on => kind != PrinterKind.none && (kind == PrinterKind.system || address.isNotEmpty);
  int get dots => paper == 58 ? 384 : 576; // printable width at 203 dpi
  double get logicalWidth => paper == 58 ? 220 : 300; // the receipt widget's width on screen

  Map<String, dynamic> toJson() => {'kind': kind.name, 'address': address, 'name': name, 'paper': paper};
  factory PrinterConf.fromJson(Object? v) {
    final m = v is Map ? v : const {};
    return PrinterConf(
      kind: PrinterKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => PrinterKind.none),
      address: '${m['address'] ?? ''}',
      name: '${m['name'] ?? ''}',
      paper: m['paper'] == 58 ? 58 : 80,
    );
  }
  PrinterConf copyWith({PrinterKind? kind, String? address, String? name, int? paper}) =>
      PrinterConf(kind: kind ?? this.kind, address: address ?? this.address, name: name ?? this.name, paper: paper ?? this.paper);
}

// printer settings of this device (each POS keeps its own under its own key)
class PrinterStore {
  static Future<Map<String, dynamic>> load(String key) async {
    final p = await SharedPreferences.getInstance();
    try {
      final v = jsonDecode(p.getString(key) ?? '{}');
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String key, Map<String, dynamic> v) async => (await SharedPreferences.getInstance()).setString(key, jsonEncode(v));
}

// ---------- drawing a widget off-screen ----------
// width = logical width; the picture is `dots` pixels wide. Images inside must already be decoded (RawImage).
Future<ui.Image> renderWidget(Widget child, {required double width, required int dots}) async {
  final ratio = dots / width;
  final boundary = RenderRepaintBoundary();
  final view = ui.PlatformDispatcher.instance.implicitView ?? ui.PlatformDispatcher.instance.views.first;
  final renderView = RenderView(
    view: view,
    child: boundary,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 30000),
      devicePixelRatio: ratio,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final build = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: Size(width, 30000), devicePixelRatio: ratio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'PlusJakartaSans', fontFamilyFallback: ['KantumruyPro'], color: Colors.black, fontSize: 13, height: 1.3),
          child: ColoredBox(color: Colors.white, child: child),
        ),
      ),
    ),
  ).attachToRenderTree(build);
  build.buildScope(root);
  build.finalizeTree();
  pipeline.flushLayout();
  pipeline.flushCompositingBits();
  pipeline.flushPaint();
  return boundary.toImage(pixelRatio: ratio);
}

// a picture from the internet decoded now, so it can be drawn right away (logos on receipts)
final Map<String, ui.Image> _pictures = {};
Future<ui.Image?> loadPicture(String url) async {
  if (url.isEmpty) return null;
  if (_pictures.containsKey(url)) return _pictures[url];
  try {
    final r = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)),
    );
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(r.data!), targetWidth: 240);
    final img = (await codec.getNextFrame()).image;
    _pictures[url] = img;
    return img;
  } catch (_) {
    return null;
  }
}

// ---------- ESC/POS ----------
// a picture → printer bytes: reset, the picture in bands (GS v 0, 1 bit per dot), feed, cut
Future<List<int>> escPosImage(ui.Image img, {bool cut = true}) async {
  final w = img.width, h = img.height;
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final bytesPerRow = (w + 7) >> 3;
  final out = BytesBuilder(copy: false)..add([0x1B, 0x40]); // ESC @ reset
  const band = 240;
  for (var y0 = 0; y0 < h; y0 += band) {
    final rows = (h - y0) < band ? h - y0 : band;
    out.add([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xff, bytesPerRow >> 8, rows & 0xff, rows >> 8]);
    final data = Uint8List(bytesPerRow * rows);
    for (var y = 0; y < rows; y++) {
      final row = (y0 + y) * w * 4;
      for (var x = 0; x < w; x++) {
        final i = row + x * 4;
        final a = rgba[i + 3];
        // dark enough (and not see-through) → a black dot
        final lum = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        final v = a < 128 ? 255 : lum;
        if (v < 150) data[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    out.add(data);
  }
  out.add([0x1B, 0x64, 0x04]); // feed 4 lines
  if (cut) out.add([0x1D, 0x56, 0x42, 0x00]); // cut
  return out.toBytes();
}

// ---------- sending ----------
class PrintError implements Exception {
  final String code; // bluetooth_off | no_permission(_settings) | not_connected | network | unsupported | failed
  const PrintError(this.code);
  @override
  String toString() => code;
}

// Android 12+: "Nearby devices" must be allowed, or the printer plugin quietly never answers (the print would hang)
Future<void> _bluetoothAllowed() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  String? r;
  try {
    r = await const MethodChannel('bizhub/perm').invokeMethod<String>('bluetooth');
  } catch (_) {
    return; // an older build without the channel: let the printer try
  }
  if (r == 'granted') return;
  throw PrintError(r == 'blocked' ? 'no_permission_settings' : 'no_permission');
}

Future<List<({String name, String mac})>> pairedBluetoothPrinters() async {
  if (kIsWeb) throw const PrintError('unsupported');
  await _bluetoothAllowed();
  if (!await PrintBluetoothThermal.bluetoothEnabled) throw const PrintError('bluetooth_off');
  final list = await PrintBluetoothThermal.pairedBluetooths;
  return [for (final b in list) (name: b.name, mac: b.macAdress)];
}

Future<void> _bluetooth(String mac, List<int> bytes) async {
  if (kIsWeb) throw const PrintError('unsupported');
  await _bluetoothAllowed();
  if (!await PrintBluetoothThermal.bluetoothEnabled) throw const PrintError('bluetooth_off');
  if (!await PrintBluetoothThermal.connectionStatus) {
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!ok) throw const PrintError('not_connected');
  }
  // small pieces: cheap printers drop data when it comes too fast
  const piece = 2048;
  for (var i = 0; i < bytes.length; i += piece) {
    final ok = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, i + piece > bytes.length ? bytes.length : i + piece));
    if (!ok) throw const PrintError('failed');
  }
}

Future<void> _system(ui.Image img, String title, int paper) async {
  final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  final widthPt = (paper == 58 ? 58 : 80) * PdfPageFormat.mm;
  final heightPt = widthPt * img.height / img.width;
  final doc = pw.Document(title: title);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthPt, heightPt + 4 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm),
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fitWidth),
    ),
  );
  await Printing.layoutPdf(name: title, onLayout: (_) async => doc.save());
}

// print one receipt-like widget on a printer
Future<void> printWidget(Widget doc, PrinterConf conf, {String title = 'Receipt', bool cut = true}) async {
  if (!conf.on) throw const PrintError('none');
  final img = await renderWidget(doc, width: conf.logicalWidth, dots: conf.dots);
  try {
    switch (conf.kind) {
      case PrinterKind.system:
        await _system(img, title, conf.paper);
      case PrinterKind.network:
        try {
          await sendToNetwork(conf.address, await escPosImage(img, cut: cut));
        } on UnsupportedError {
          throw const PrintError('unsupported');
        } catch (e) {
          if (e is PrintError) rethrow;
          throw const PrintError('network');
        }
      case PrinterKind.bluetooth:
        await _bluetooth(conf.address, await escPosImage(img, cut: cut));
      case PrinterKind.none:
        break;
    }
  } finally {
    img.dispose();
  }
}
