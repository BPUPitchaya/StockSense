class Position {
  final int? id;
  final String ticker;
  final double buyPrice;
  final int quantity;
  final String date;
  final String? createdAt;

  Position({
    this.id,
    required this.ticker,
    required this.buyPrice,
    required this.quantity,
    required this.date,
    this.createdAt,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      id: json['id'],
      ticker: json['ticker'] ?? '',
      buyPrice: (json['buy_price'] as num).toDouble(),
      quantity: json['quantity'] ?? 0,
      date: json['date'] ?? '',
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ticker': ticker,
      'buy_price': buyPrice,
      'quantity': quantity,
      'date': date,
    };
  }
}