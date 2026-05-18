class Signal {
  final String ticker;
  final double currentPrice;
  final double? ma50;
  final double? ma200;
  final double? rsi;
  final String signal;
  final String date;

  Signal({
    required this.ticker,
    required this.currentPrice,
    this.ma50,
    this.ma200,
    this.rsi,
    required this.signal,
    required this.date,
  });

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      ticker: json['ticker'] ?? '',
      currentPrice: (json['current_price'] as num).toDouble(),
      ma50: json['ma50']?.toDouble(),
      ma200: json['ma200']?.toDouble(),
      rsi: json['rsi']?.toDouble(),
      signal: json['signal'] ?? 'HOLD',
      date: json['date'] ?? '',
    );
  }
}