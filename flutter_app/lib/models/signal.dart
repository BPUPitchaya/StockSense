class Signal {
  final String ticker;
  final String? name;
  final double currentPrice;
  final double? ma50;
  final double? ma200;
  final double? rsi;
  final String signal;
  final String date;
  final double? percentChange;

  Signal({
    required this.ticker,
    this.name,
    required this.currentPrice,
    this.ma50,
    this.ma200,
    this.rsi,
    required this.signal,
    required this.date,
    this.percentChange,
  });

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      ticker: json['ticker'] ?? '',
      name: json['name'],
      currentPrice: (json['current_price'] as num).toDouble(),
      ma50: json['ma50']?.toDouble(),
      ma200: json['ma200']?.toDouble(),
      rsi: json['rsi']?.toDouble(),
      signal: json['signal'] ?? 'HOLD',
      date: json['date'] ?? '',
      percentChange: json['percent_change']?.toDouble(),
    );
  }
}