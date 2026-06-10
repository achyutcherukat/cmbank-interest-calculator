import 'dart:convert';

import 'package:http/http.dart' as http;

class GoldRateResult {
  final double rate24k;
  final double rate22k;
  const GoldRateResult({required this.rate24k, required this.rate22k});
}

class GoldRateService {
  static const _timeout = Duration(seconds: 12);

  // Gold spot price in USD per troy oz (free, no key)
  static const _goldUrl = 'https://metals.live/api/v1/spot';

  // USD → INR exchange rate (free, no key)
  static const _fxUrl =
      'https://api.exchangerate-api.com/v4/latest/USD';

  // Troy oz → grams conversion
  static const _troyOzGrams = 31.1035;

  static Future<GoldRateResult> fetchLiveRates() async {
    final responses = await Future.wait([
      http.get(Uri.parse(_goldUrl)).timeout(_timeout),
      http.get(Uri.parse(_fxUrl)).timeout(_timeout),
    ]);

    final goldResp = responses[0];
    final fxResp = responses[1];

    if (goldResp.statusCode != 200) {
      throw Exception(
          'Gold price API returned ${goldResp.statusCode}. Check internet connection.');
    }
    if (fxResp.statusCode != 200) {
      throw Exception(
          'Currency rate API returned ${fxResp.statusCode}. Check internet connection.');
    }

    final dynamic goldJson = jsonDecode(goldResp.body);
    final dynamic fxJson = jsonDecode(fxResp.body);

    // metals.live returns [{gold: ..., silver: ...}] (array) or {gold: ...}
    final double goldUsdOz;
    if (goldJson is List) {
      goldUsdOz = (goldJson.first['gold'] as num).toDouble();
    } else if (goldJson is Map) {
      goldUsdOz = (goldJson['gold'] as num).toDouble();
    } else {
      throw Exception('Unexpected gold price API response format.');
    }

    final double inrPerUsd =
        (fxJson['rates']['INR'] as num).toDouble();

    // Price per gram in INR
    final double rate24k = (goldUsdOz * inrPerUsd) / _troyOzGrams;
    final double rate22k = rate24k * (22.0 / 24.0);

    return GoldRateResult(rate24k: rate24k, rate22k: rate22k);
  }
}
