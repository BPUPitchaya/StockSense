import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/signal.dart';
import '../models/position.dart';
import '../models/historical_data.dart';
import '../config.dart';

class ApiService {
  static String get baseUrl => Config.apiBaseUrl;

  // Authentication methods
  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _saveToken(data['token']);
      return data;
    } else {
      throw Exception('Failed to login: ${response.body}');
    }
  }

  static Future<void> signup(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/signup'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to signup: ${response.body}');
    }
  }

  static Future<void> logout() async {
    await _removeToken();
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
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Signal.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load signals');
    }
  }

  static Future<List<Position>> getPortfolio() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/portfolio'), headers: headers);

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => Position.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load portfolio');
    }
  }

  static Future<void> addPosition(Position position) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/portfolio'),
      headers: headers,
      body: json.encode(position.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to add position');
    }
  }

  static Future<void> deletePosition(int positionId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/portfolio/$positionId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete position');
    }
  }

  static Future<List<String>> getWatchlist() async {
    final response = await http.get(Uri.parse('$baseUrl/watchlist'));

    if (response.statusCode == 200) {
      Map<String, dynamic> data = json.decode(response.body);
      return List<String>.from(data['watchlist']);
    } else {
      throw Exception('Failed to load watchlist');
    }
  }

  static Future<Signal> searchStock(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/search/$ticker'));

    if (response.statusCode == 200) {
      Map<String, dynamic> data = json.decode(response.body);
      return Signal.fromJson(data);
    } else if (response.statusCode == 404) {
      throw Exception('Stock not found or insufficient data');
    } else {
      throw Exception('Failed to search stock');
    }
  }

  static Future<List<HistoricalData>> getStockHistory(String ticker, String period) async {
    final response = await http.get(Uri.parse('$baseUrl/history/$ticker?period=$period'));

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      return data.map((json) => HistoricalData.fromJson(json)).toList();
    } else if (response.statusCode == 404) {
      throw Exception('Stock not found or insufficient data');
    } else {
      throw Exception('Failed to fetch stock history');
    }
  }

  static Future<Map<String, dynamic>> getStockInfo(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/info/$ticker'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      throw Exception('Stock not found or insufficient data');
    } else {
      throw Exception('Failed to fetch stock info');
    }
  }

  static Future<Map<String, dynamic>> getPredictions() async {
    final response = await http.get(Uri.parse('$baseUrl/predictions'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch predictions');
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
      throw Exception('Failed to set budget');
    }
  }

  static Future<Map<String, dynamic>?> getBudget() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/budget'), headers: headers);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to fetch budget');
    }
  }

  static Future<Map<String, dynamic>> getBudgetRecommendations() async {
    final response = await http.get(Uri.parse('$baseUrl/budget-recommendations'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      throw Exception('No budget set. Please set a budget first.');
    } else {
      throw Exception('Failed to fetch budget recommendations');
    }
  }

  static Future<void> updatePosition(int positionId, Position position) async {
    final response = await http.put(
      Uri.parse('$baseUrl/portfolio/$positionId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(position.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update position');
    }
  }

  static Future<Map<String, dynamic>> getPortfolioValue() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$baseUrl/portfolio/value'), headers: headers);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch portfolio value');
    }
  }

  static Future<List<String>> getPersonalWatchlist() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/personal-watchlist'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<String>.from(data['personal_watchlist']);
    } else {
      throw Exception('Failed to load personal watchlist');
    }
  }

  static Future<void> addToPersonalWatchlist(String ticker) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/personal-watchlist/$ticker'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to add to personal watchlist');
    }
  }

  static Future<void> removeFromPersonalWatchlist(String ticker) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/personal-watchlist/$ticker'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove from personal watchlist');
    }
  }

  static Future<Map<String, dynamic>> validateStock(String ticker) async {
    final response = await http.get(Uri.parse('$baseUrl/validate-stock/$ticker'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to validate stock');
    }
  }
}