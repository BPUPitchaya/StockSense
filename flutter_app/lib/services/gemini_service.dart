import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';

class GeminiService {
  static Future<String> getStockEvaluation(String ticker, Map<String, dynamic> metrics, {bool ownsStock = false}) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai-analysis'),
        headers: headers,
        body: json.encode({
          'ticker': ticker,
          'owns_stock': ownsStock,
          'rsi': metrics['rsi'],
          'ma50': metrics['ma50'],
          'ma200': metrics['ma200'],
          'signal': metrics['signal'],
          'current_price': metrics['current_price'],
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['analysis'] ?? 'No analysis available';
      } else {
        throw Exception('Failed to get AI analysis');
      }
    } catch (e) {
      return 'Unable to load analysis. Please try again later.';
    }
  }
}
