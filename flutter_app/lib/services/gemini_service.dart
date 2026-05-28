import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static GenerativeModel? _model;

  static GenerativeModel get model {
    _model ??= GenerativeModel(
      model: 'gemini-3.1-flash-lite', // 500 RPD free tier
      apiKey: _apiKey,
    );
    return _model!;
  }

  static Future<String> getStockEvaluation(String ticker, Map<String, dynamic> metrics) async {
    if (_apiKey.isEmpty) {
      return 'API key not configured. Run with --dart-define=GEMINI_API_KEY=your_key';
    }

    final prompt = '''
Analyze the stock $ticker with these metrics:
- Current Price: ${metrics['current_price']}
- Signal: ${metrics['signal']}
- RSI: ${metrics['rsi'] ?? 'N/A'}
- 50-day MA: ${metrics['ma50'] ?? 'N/A'}
- 200-day MA: ${metrics['ma200'] ?? 'N/A'}
- Industry: ${metrics['industry'] ?? 'N/A'}
- Market Cap: ${metrics['market_cap'] ?? 'N/A'}

Provide a brief structured analysis with:
## Strengths
## Risks
## Outlook

Keep it concise (under 150 words total).
''';

    final response = await model.generateContent([Content.text(prompt)]);
    return response.text ?? 'No response generated.';
  }
}
