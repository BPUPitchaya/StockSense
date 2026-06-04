import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';

class PredictionWatchlistScreen extends StatefulWidget {
  const PredictionWatchlistScreen({super.key});

  @override
  State<PredictionWatchlistScreen> createState() => _PredictionWatchlistScreenState();
}

class _PredictionWatchlistScreenState extends State<PredictionWatchlistScreen> {
  List<dynamic> _watchlist = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    CurrencyService.load().then((_) {
      if (mounted) {
        setState(() {});
        _loadWatchlist();
      }
    });
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.getPredictionWatchlist();
      setState(() {
        _watchlist = response['watchlist'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromWatchlist(String ticker) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.removeFromWatchlist(ticker);
      await _loadWatchlist();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatPrice(double? price) {
    if (price == null) return 'N/A';
    final localPrice = CurrencyService.convert(price);
    final symbol = CurrencyService.symbol;
    if (CurrencyService.currency == 'JPY' || CurrencyService.currency == 'KRW') {
      return '$symbol${localPrice.toStringAsFixed(0)}';
    }
    return '$symbol${localPrice.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track'),
      ),
      body: ResponsiveBody(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Watchlist',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Stocks are automatically tracked from the day you add them to your watchlist.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _watchlist.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bookmark_border,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No stocks in watchlist',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Add stocks from the Signals screen to start tracking',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadWatchlist,
                            child: ListView.builder(
                              itemCount: _watchlist.length,
                              itemBuilder: (context, index) {
                                final item = _watchlist[index];
                                final percentChange = item['percent_change'] ?? 0.0;
                                final isPositive = percentChange >= 0;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    title: Text(
                                      item['ticker'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text('Added: ${_formatDate(item['added_date'])}'),
                                        Text('Added Price: ${_formatPrice(item['added_price'])}'),
                                        if (item['current_price'] != null)
                                          Text('Current Price: ${_formatPrice(item['current_price'])}'),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPositive
                                                ? Colors.green.withOpacity(0.1)
                                                : Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(2)}%',
                                            style: TextStyle(
                                              color: isPositive
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline),
                                          color: Colors.grey,
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () =>
                                              _removeFromWatchlist(item['ticker']),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
