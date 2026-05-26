import 'api_service.dart';

class CurrencyService {
  static String _currency = 'USD';
  static String _symbol = '\$';
  static Map<String, dynamic> _rates = {};

  static String get currency => _currency;
  static String get symbol => _symbol;

  static Future<void> load() async {
    try {
      final results = await Future.wait([
        ApiService.getUserCurrency(),
        ApiService.getExchangeRates(),
      ]);
      final userCurrency = results[0] as Map<String, dynamic>;
      final ratesData = results[1] as Map<String, dynamic>;
      _currency = userCurrency['currency'] ?? 'USD';
      _symbol = userCurrency['symbol'] ?? '\$';
      _rates = (ratesData['rates'] as Map<String, dynamic>?) ?? {};
    } catch (_) {
      // Keep existing values on failure
    }
  }

  static Future<void> reload() => load();

  static double toUsd(double localAmount) {
    if (_currency == 'USD' || !_rates.containsKey(_currency)) return localAmount;
    return localAmount / (_rates[_currency] as num).toDouble();
  }

  static double convert(double usdPrice) {
    if (_currency == 'USD' || !_rates.containsKey(_currency)) return usdPrice;
    return usdPrice * (_rates[_currency] as num).toDouble();
  }

  static String format(double usdPrice) {
    final converted = convert(usdPrice);
    if (_currency == 'KRW') {
      return '${converted.toStringAsFixed(0)}$_symbol';
    }
    if (_currency == 'JPY') {
      return '$_symbol${converted.toStringAsFixed(0)}';
    }
    return '$_symbol${converted.toStringAsFixed(2)}';
  }
}
