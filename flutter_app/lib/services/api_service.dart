import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/signal.dart';
import '../models/historical_data.dart';

class ApiService {
  static String baseUrl = Config.apiBaseUrl;

  // Token management
  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // Authentication
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _saveToken(data['access_token']);
      return data;
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> signup(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/signup'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Signup failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to send reset email: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'token': token, 'new_password': newPassword}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to reset password: ${response.body}');
    }
  }

  static Future<void> logout() async {
    await _removeToken();
  }

  // Admin methods
  static Future<Map<String, dynamic>> adminLogin(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Admin login failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getAllUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/admin/users'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get users: ${response.body}');
    }
  }

  static Future<void> deleteUser(int userId) async {
    final response = await http.delete(Uri.parse('$baseUrl/admin/users/$userId'));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getAdminStatistics() async {
    final response = await http.get(Uri.parse('$baseUrl/admin/statistics'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get admin statistics: ${response.body}');
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<List<Signal>> getSignals({bool refresh = false}) async {
    final headers = await _getHeaders();
    final url = refresh ? '$baseUrl/signals?refresh=true' : '$baseUrl/signals';
    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Signal.fromJson(json)).toList();
    } else {
      throw Exception('Failed to get signals: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> addPosition(Map<String, dynamic> position) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/portfolio'),
      headers: headers,
      body: json.encode(position),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to add position: ${response.body}');
    }
  }

  static Future<List<dynamic>> getPortfolio() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/portfolio'), headers: headers);

    if (response.statusCode == 200) {
      return json.decode(response.body)['positions'];
    } else {
      throw Exception('Failed to get portfolio: ${response.body}');
    }
  }

  static Future<void> deletePosition(int positionId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/portfolio/$positionId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete position: ${response.body}');
    }
  }

  static Future<double> getPortfolioValue() async {
    final positions = await getPortfolio();
    double totalValue = 0;
    for (var pos in positions) {
      totalValue += pos['buy_price'] * pos['quantity'];
    }
    return totalValue;
  }

  static Future<double> getBudget() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/budget'), headers: headers);

    if (response.statusCode == 200) {
      return json.decode(response.body)['budget'].toDouble();
    } else {
      throw Exception('Failed to get budget: ${response.body}');
    }
  }

  static Future<void> setBudget(double amount) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/budget'),
      headers: headers,
      body: json.encode({'amount': amount}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to set budget: ${response.body}');
    }
  }

  static Future<List<String>> getWatchlist() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/watchlist'), headers: headers);

    if (response.statusCode == 200) {
      return List<String>.from(json.decode(response.body)['watchlist']);
    } else {
      throw Exception('Failed to get watchlist: ${response.body}');
    }
  }

  static Future<void> addToWatchlist(String ticker) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/watchlist'),
      headers: headers,
      body: json.encode({'ticker': ticker}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to add to watchlist: ${response.body}');
    }
  }

  static Future<void> removeFromWatchlist(String ticker) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/watchlist/$ticker'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove from watchlist: ${response.body}');
    }
  }

  // Prediction Watchlist
  static Future<Map<String, dynamic>> getPredictionWatchlist() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/prediction-watchlist'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get prediction watchlist: ${response.body}');
    }
  }

  static Future<void> addToPredictionWatchlist(String ticker, double addedPrice) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/prediction-watchlist'),
      headers: headers,
      body: json.encode({'ticker': ticker, 'added_price': addedPrice}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to add to prediction watchlist: ${response.body}');
    }
  }

  static Future<void> removeFromPredictionWatchlist(String ticker) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/prediction-watchlist/$ticker'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove from prediction watchlist: ${response.body}');
    }
  }

  // Additional methods for other screens
  static Future<Map<String, dynamic>> searchStock(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/search/$ticker'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to search stock: ${response.body}');
    }
  }

  static Future<List<HistoricalData>> getStockHistory(String ticker, String period) async {
    final response = await http.get(Uri.parse('$baseUrl/history/$ticker?period=$period'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => HistoricalData.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to get stock history: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getStockInfo(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/info/$ticker'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get stock info: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getPredictions() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/predictions'), headers: headers);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 503) {
      throw Exception('Prediction service is temporarily unavailable. Please try again in a moment.');
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Session expired. Please log in again.');
    } else {
      try {
        final body = json.decode(response.body);
        final detail = body['detail'];
        if (detail is String) throw Exception(detail);
      } catch (_) {}
      throw Exception('Could not load predictions. Please try again.');
    }
  }

  static Future<List<Map<String, dynamic>>> getPredictionHistory(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/predictions/history/$ticker'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['predictions'] ?? []);
    } else {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getProjection(String ticker, String period) async {
    final response = await http.get(Uri.parse('$baseUrl/projection/$ticker?period=$period'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get projection: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getMarketStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/market/status'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return {
        'is_open': false,
        'is_premarket': false,
        'error': 'Failed to fetch market status'
      };
    }
  }

  static Future<void> updatePosition(int positionId, Map<String, dynamic> position) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/portfolio/$positionId'),
      headers: headers,
      body: json.encode(position),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update position: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getBudgetRecommendations({
    String stockSource = 'watchlist',
    String goal = '',
    String timeHorizon = '5',
    List<String> customStocks = const [],
  }) async {
    final headers = await _getHeaders();
    final queryParams = {
      'stock_source': stockSource,
      'goal': goal,
      'time_horizon': timeHorizon,
      if (customStocks.isNotEmpty) 'custom_stocks': customStocks.join(','),
    };
    final uri = Uri.parse('$baseUrl/budget-recommendations')
        .replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get budget recommendations: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> validateStock(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/validate-stock/$ticker'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to validate stock: ${response.body}');
    }
  }

  // Aliases for personal watchlist methods
  static Future<List<String>> getPersonalWatchlist() async => getWatchlist();
  static Future<void> addToPersonalWatchlist(String ticker) async => addToWatchlist(ticker);
  static Future<void> removeFromPersonalWatchlist(String ticker) async => removeFromWatchlist(ticker);

  // Currency methods
  static Future<List<dynamic>> getCurrencies() async {
    final response = await http.get(Uri.parse('$baseUrl/currencies'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['currencies'];
    } else {
      throw Exception('Failed to get currencies');
    }
  }

  static Future<Map<String, dynamic>> getUserCurrency() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/user/currency'), headers: headers);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get user currency');
    }
  }

  static Future<void> setUserCurrency(String currency) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/user/currency'),
      headers: headers,
      body: json.encode({'currency': currency}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set currency: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getExchangeRates() async {
    final response = await http.get(Uri.parse('$baseUrl/exchange-rates'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get exchange rates');
    }
  }
}