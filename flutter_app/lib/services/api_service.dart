import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

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

  static Future<List<Signal>> getSignals() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/signals'), headers: headers);

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
}

class Signal {
  final String ticker;
  final String prediction;
  final double confidence;
  final double score;
  final double potentialChange;
  final String? category;

  Signal({
    required this.ticker,
    required this.prediction,
    required this.confidence,
    required this.score,
    required this.potentialChange,
    this.category,
  });

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      ticker: json['ticker'],
      prediction: json['prediction'],
      confidence: json['confidence'].toDouble(),
      score: json['score'].toDouble(),
      potentialChange: json['potential_change'].toDouble(),
      category: json['category'],
    );
  }
}