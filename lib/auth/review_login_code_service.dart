import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class ReviewLoginCodeService {
  ReviewLoginCodeService({http.Client? client})
    : _client = client ?? http.Client();

  static const _relay = String.fromEnvironment('REVIEW_RELAY');
  static const _key = 'mithka-review-relay';
  static const _tokenBytes = <int>[
    60,
    15,
    30,
    36,
    38,
    7,
    28,
    61,
    40,
    34,
    14,
    55,
    24,
    104,
    16,
    83,
    91,
    22,
    12,
    55,
    49,
    62,
    59,
    62,
    45,
    120,
    42,
    44,
    36,
    56,
    22,
    62,
    106,
    71,
    84,
    39,
    21,
    24,
    84,
    10,
    2,
    95,
    34,
    92,
  ];

  final http.Client _client;

  static _ReviewRelayConfig? get _config => _ReviewRelayConfig.parse(_relay);

  static bool isReviewPhone(String phone) {
    final config = _config;
    if (config == null) return false;
    return _sha256Hex(_digits(phone)) == config.phoneHash;
  }

  Future<String?> fetchCode() async {
    final config = _config;
    if (config == null) return null;

    final response = await _client
        .get(
          Uri.parse('${config.relayUrl}/code'),
          headers: {
            'authorization': 'Bearer ${_decode(_tokenBytes)}',
            'cache-control': 'no-store',
          },
        )
        .timeout(const Duration(seconds: 6));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('review code relay returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final code = decoded['code'];
    if (code is! String || !RegExp(r'^\d{3,8}$').hasMatch(code)) return null;
    return code;
  }

  static String _sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String _decode(List<int> bytes) {
    final key = utf8.encode(_key);
    final decoded = <int>[
      for (var i = 0; i < bytes.length; i += 1) bytes[i] ^ key[i % key.length],
    ];
    return utf8.decode(decoded);
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');
}

class _ReviewRelayConfig {
  const _ReviewRelayConfig({required this.relayUrl, required this.phoneHash});

  final String relayUrl;
  final String phoneHash;

  static _ReviewRelayConfig? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final separator = trimmed.lastIndexOf('|');
    if (separator <= 0 || separator == trimmed.length - 1) return null;

    final relayUrl = trimmed.substring(0, separator).trim();
    final phoneHash = trimmed.substring(separator + 1).trim().toLowerCase();
    if (!relayUrl.startsWith('https://')) return null;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(phoneHash)) return null;

    return _ReviewRelayConfig(
      relayUrl: relayUrl.replaceFirst(RegExp(r'/+$'), ''),
      phoneHash: phoneHash,
    );
  }
}
