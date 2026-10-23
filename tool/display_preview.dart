// A preview of the customer screen for the web (tests only — not part of the app): ?mode=idle|cart|pay|thanks
import 'package:bizhub_pos/features/mart/mart_display.dart';
import 'package:flutter/material.dart';

void main() {
  final mode = Uri.base.queryParameters['mode'] ?? 'cart';
  final shop = {'name': 'Lucky Mart', 'logo': ''};
  final lines = [
    {'key': 'a', 'name': 'Coca-Cola 330ml', 'qty': 2, 'total': 1.2},
    {'key': 'b', 'name': 'Angkor Beer can', 'qty': 6, 'total': 4.8},
    {'key': 'c', 'name': 'Banana (kg)', 'qty': 1.25, 'total': 1.88},
    {'key': 'd', 'name': 'នំប៉័ងបារាំង (French bread)', 'qty': 3, 'total': 1.5},
    {'key': 'e', 'name': 'Milk 1L', 'qty': 1, 'total': 2.2},
  ];
  final pics = <String, Map<String, Object?>>{
    'idle': {
      'mode': 'idle',
      'shop': shop,
      'currency': 'USD',
      'color': '',
      'promos': ['Buy 2 get 1 free · Drinks', '10% off fruit', 'Happy hour 5–7pm'],
    },
    'cart': {
      'mode': 'cart',
      'shop': shop,
      'currency': 'USD',
      'color': '#0F766E',
      'lines': lines,
      'count': 13.25,
      'promos_applied': [
        {'name': 'Buy 2 get 1 free · Drinks', 'amount': 0.8},
      ],
      'discount': 0.5,
      'points_value': 0,
      'total': 10.28,
      'total_khr': 42200,
      'member': 'Srey Pov',
      'member_points': 120,
    },
    'pay': {
      'mode': 'pay',
      'shop': shop,
      'currency': 'USD',
      'color': '',
      'lines': lines,
      'count': 13.25,
      'promos_applied': [],
      'discount': 0,
      'points_value': 0,
      'total': 11.58,
      'total_khr': 47500,
      'member': '',
      'qr': 'http://127.0.0.1:5182/qr.png',
      'qr_label': 'ABA · LUCKY MART',
    },
    'thanks': {'mode': 'thanks', 'shop': shop, 'currency': 'USD', 'color': '', 'total': 11.58, 'change': 8.42, 'change_khr': 34500, 'earned': 11},
  };
  runApp(MartDisplayApp(preview: pics[mode]));
}
