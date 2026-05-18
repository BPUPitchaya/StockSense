import 'package:flutter/material.dart';
import '../models/signal.dart';
import '../services/api_service.dart';
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
  Signal? searchedSignal;
  bool isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadSignals();
  }

  Future<void> _loadSignals() async {
    setState(() {
      isLoading = true;
      error = null;
      searchedSignal = null;
    });

    try {
      final loadedSignals = await ApiService.getSignals();
      if (mounted) {
        setState(() {
          signals = loadedSignals;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

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

  Color _getSignalColor(String signal) {
    switch (signal.toUpperCase()) {
      case 'BUY':
        return Colors.green;
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
              ? _buildSignalCard(searchedSignal!)
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
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockDetailScreen(signal: signal),
            ),
          );
        },
        child: ListTile(
          title: Text(
            signal.ticker,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Current Price: \$${signal.currentPrice.toStringAsFixed(2)}'),
              if (signal.ma50 != null)
                Text('50-day MA: \$${signal.ma50!.toStringAsFixed(2)}'),
              if (signal.ma200 != null)
                Text('200-day MA: \$${signal.ma200!.toStringAsFixed(2)}'),
              if (signal.rsi != null)
                Text('RSI: ${signal.rsi!.toStringAsFixed(2)}'),
              Text('Date: ${signal.date}'),
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