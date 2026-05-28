import 'package:flutter/material.dart';
import 'dart:ui';
import '../models/signal.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';
import '../theme.dart';
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
    if (personalWatchlist.length >= 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watchlist is full (max 5 stocks). Remove one first.')),
        );
      }
      return;
    }
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
          SnackBar(content: Text('Added $ticker to watchlist')),
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
        return AppColors.up;
      case 'BUY':
        return AppColors.up;
      case 'STRONG SELL':
        return AppColors.down;
      case 'SELL':
        return AppColors.down;
      default:
        return AppColors.textMuted;
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
      body: ResponsiveBody(
        child: isSearching
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
                            ? const EmptyState(
                                icon: Icons.trending_up,
                                title: 'No signals available',
                                subtitle: 'Pull down to refresh or search for a stock above.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: signals.length,
                                itemBuilder: (context, index) {
                                  final signal = signals[index];
                                  return _buildSignalCard(signal);
                                },
                              ),
      ),
    );
  }

  Widget _buildSignalCard(Signal signal) {
    final isInWatchlist = inWatchlist[signal.ticker] ?? false;
    final pc = signal.percentChange;
    final isUp = (pc ?? 0) >= 0;
    final changeColor = isUp ? AppColors.up : AppColors.down;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StockDetailScreen(signal: signal),
            ),
          );
          if (mounted) _clearSearch();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: ticker + signal pill + star
              Row(
                children: [
                  Text(
                    signal.ticker,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SignalPill(
                    label: signal.signal.toUpperCase(),
                    color: _getSignalColor(signal.signal),
                    subtle: true,
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (isInWatchlist) {
                        _removeFromPersonalWatchlist(signal.ticker);
                      } else {
                        _addToPersonalWatchlist(signal.ticker);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        isInWatchlist ? Icons.star : Icons.star_border,
                        size: 20,
                        color: isInWatchlist ? AppColors.text : AppColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              if (signal.name != null) ...[
                const SizedBox(height: 2),
                Text(
                  signal.name!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 12),
              // Price + change row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(signal.currentPrice),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (pc != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUp ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 14,
                            color: changeColor,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${pc.abs().toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: changeColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (signal.ma50 != null || signal.ma200 != null || signal.rsi != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (signal.ma50 != null)
                      _miniStat('MA50', _formatPrice(signal.ma50!)),
                    if (signal.ma200 != null)
                      _miniStat('MA200', _formatPrice(signal.ma200!)),
                    if (signal.rsi != null)
                      _miniStat('RSI', signal.rsi!.toStringAsFixed(1)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textFaint,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}