import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import 'stock_detail_screen.dart';

class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key});

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  List<Signal> signals = [];
  bool isLoading = true;
  String? error;
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? searchedSignal;
  bool isSearching = false;
  List<String> personalWatchlist = [];
  Map<String, bool> inWatchlist = {};
  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadPersonalWatchlist();
  }

  Future<void> _loadAll() async {
    setState(() { isLoading = true; error = null; searchedSignal = null; });
    try {
      final results = await Future.wait([
        ApiService.getSignals(),
        CurrencyService.load(),
      ]);
      if (mounted) {
        setState(() {
          signals = results[0] as List<Signal>;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { error = e.toString(); isLoading = false; });
      }
    }
  }

  String _formatPrice(double usdPrice) => CurrencyService.format(usdPrice);

  Future<void> _loadSignals() => _loadAll();

  Future<void> _searchStock() async {
    final ticker = _searchController.text.trim().toUpperCase();
    if (ticker.isEmpty) return;

    setState(() {
      isSearching = true;
      error = null;
    });

    try {
      final signal = await ApiService.searchStock(ticker);
      if (mounted) {
        setState(() {
          searchedSignal = signal;
          isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isSearching = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      searchedSignal = null;
    });
  }

  Future<void> _loadPersonalWatchlist() async {
    try {
      final watchlist = await ApiService.getPersonalWatchlist();
      if (mounted) {
        setState(() {
          personalWatchlist = watchlist;
          inWatchlist = {for (var ticker in watchlist) ticker: true};
        });
      }
    } catch (e) {
      // Silently fail - personal watchlist is optional
    }
  }

  Future<void> _addToPersonalWatchlist(String ticker) async {
    try {
      final validation = await ApiService.validateStock(ticker);
      
      if (!validation['valid']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot add $ticker: ${validation['reason']}')),
          );
        }
        return;
      }
      
      if (validation['is_etf']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ETFs are not supported for predictions')),
          );
        }
        return;
      }
      
      await ApiService.addToPersonalWatchlist(ticker);
      await _loadPersonalWatchlist();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $ticker to personal watchlist')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add $ticker: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _removeFromPersonalWatchlist(String ticker) async {
    try {
      await ApiService.removeFromPersonalWatchlist(ticker);
      await _loadPersonalWatchlist();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $ticker from personal watchlist')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove $ticker: ${e.toString()}')),
        );
      }
    }
  }

  Color _getSignalColor(String signal) {
    switch (signal.toUpperCase()) {
      case 'STRONG BUY':
        return Colors.green.shade700;
      case 'BUY':
        return Colors.green;
      case 'STRONG SELL':
        return Colors.red.shade700;
      case 'SELL':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trading Signals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSignals,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search stock (e.g., AAPL)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _searchStock(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchStock,
                ),
                if (searchedSignal != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  ),
              ],
            ),
          ),
        ),
      ),
      body: isSearching
          ? const Center(child: CircularProgressIndicator())
          : searchedSignal != null
              ? _buildSignalCard(Signal.fromJson(searchedSignal!))
              : isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Error: $error'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadSignals,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : signals.isEmpty
                          ? const Center(child: Text('No signals available'))
                          : ListView.builder(
                              itemCount: signals.length,
                              itemBuilder: (context, index) {
                                final signal = signals[index];
                                return _buildSignalCard(signal);
                              },
                            ),
    );
  }

  Widget _buildSignalCard(Signal signal) {
    final isInWatchlist = inWatchlist[signal.ticker] ?? false;
    
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () async {
          await Navigator.push(            context,
            MaterialPageRoute(
              builder: (context) => StockDetailScreen(signal: signal),
            ),
          );
          if (mounted) {
            _clearSearch();
          }
        },
        child: ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                signal.ticker,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(
                  isInWatchlist ? Icons.star : Icons.star_border,
                  color: isInWatchlist ? Colors.black : null,
                ),
                onPressed: () {
                  if (isInWatchlist) {
                    _removeFromPersonalWatchlist(signal.ticker);
                  } else {
                    _addToPersonalWatchlist(signal.ticker);
                  }
                },
                tooltip: isInWatchlist ? 'Remove from watchlist' : 'Add to watchlist',
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (signal.name != null)
                Text(
                  signal.name!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              const SizedBox(height: 8),
              Text('Current Price: ${_formatPrice(signal.currentPrice)}'),
              if (signal.ma50 != null)
                Text('50-day MA: ${_formatPrice(signal.ma50!)}'),
              if (signal.ma200 != null)
                Text('200-day MA: ${_formatPrice(signal.ma200!)}'),
              if (signal.rsi != null)
                Text('RSI: ${signal.rsi!.toStringAsFixed(2)}'),
              if (signal.percentChange != null)
                Text(
                  "Today's Change: ${signal.percentChange! >= 0 ? '+' : ''}${signal.percentChange!.toStringAsFixed(2)}%",
                  style: TextStyle(
                    color: signal.percentChange! >= 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: _getSignalColor(signal.signal),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              signal.signal,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}