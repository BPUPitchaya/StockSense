import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
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
  Map<String, dynamic>? marketStatus;
  
  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadPersonalWatchlist();
    _loadMarketStatus();
  }

  Future<void> _loadAll() async {
    setState(() { isLoading = true; error = null; searchedSignal = null; });
    try {
      final results = await Future.wait([
        ApiService.getSignals(refresh: true),
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

  String _formatPrice(double usdPrice, String? currency) {
    // If user prefers native currency and stock has a native currency, use it
    if (CurrencyService.useNativeCurrency && currency != null && currency != 'USD') {
      final currencySymbols = {
        'USD': '\$', 'AUD': 'A\$', 'NZD': 'NZ\$', 'GBP': '£',
        'EUR': '€', 'JPY': '¥', 'CNY': '¥', 'CAD': 'C\$',
        'HKD': 'HK\$', 'SGD': 'S\$', 'KRW': '₩', 'INR': '₹',
      };
      final sym = currencySymbols[currency] ?? currency;
      if (currency == 'JPY' || currency == 'KRW') {
        return '$sym${usdPrice.toStringAsFixed(0)}';
      }
      return '$sym${usdPrice.toStringAsFixed(2)}';
    }
    
    // Otherwise use user's preferred currency
    final converted = CurrencyService.convert(usdPrice);
    if (CurrencyService.currency == 'KRW') {
      return '${converted.toStringAsFixed(0)}${CurrencyService.symbol}';
    }
    if (CurrencyService.currency == 'JPY') {
      return '${CurrencyService.symbol}${converted.toStringAsFixed(0)}';
    }
    return '${CurrencyService.symbol}${converted.toStringAsFixed(2)}';
  }

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
          isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$ticker" not found. Check the ticker and try again.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      searchedSignal = null;
    });
  }

  Future<void> _loadMarketStatus() async {
    try {
      final status = await ApiService.getMarketStatus();
      if (mounted) {
        setState(() {
          marketStatus = status;
        });
      }
    } catch (e) {
      // Silently fail - market status is optional
    }
  }

  void _showMarketHoursDialog() {
    if (marketStatus == null) return;
    
    // Parse UTC times and convert to local timezone
    final now = DateTime.now();
    final localOffset = now.timeZoneOffset;
    final localOffsetHours = localOffset.inHours;
    final localOffsetSign = localOffsetHours >= 0 ? '+' : '';
    
    // Parse market open/close UTC times
    final openUtcParts = marketStatus!['market_open_utc'].split(':');
    final closeUtcParts = marketStatus!['market_close_utc'].split(':');
    final openUtcHour = int.parse(openUtcParts[0]);
    final closeUtcHour = int.parse(closeUtcParts[0]);
    
    // Convert to local time
    final openLocalHour = (openUtcHour + localOffsetHours) % 24;
    final closeLocalHour = (closeUtcHour + localOffsetHours) % 24;
    final openLocalTime = '${openLocalHour.toString().padLeft(2, '0')}:${openUtcParts[1]}';
    final closeLocalTime = '${closeLocalHour.toString().padLeft(2, '0')}:${closeUtcParts[1]}';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              marketStatus!['is_open'] ? Icons.wb_sunny : Icons.nights_stay,
              color: marketStatus!['is_open'] ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            const Text('US Market Hours'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${marketStatus!['is_open'] ? 'Open' : marketStatus!['is_premarket'] ? 'Pre-market' : 'Closed'}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: marketStatus!['is_open'] ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Regular Hours (ET):'),
            const SizedBox(height: 4),
            Text('Open: ${marketStatus!['market_open_et']}'),
            Text('Close: ${marketStatus!['market_close_et']}'),
            const SizedBox(height: 12),
            Text('Regular Hours (Your Time - UTC$localOffsetSign$localOffsetHours):'),
            const SizedBox(height: 4),
            Text('Open: $openLocalTime'),
            Text('Close: $closeLocalTime'),
            const SizedBox(height: 12),
            Text('Current Time (ET): ${marketStatus!['current_time_et']}'),
            Text('Current Time (Your Time): ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
    return PopScope(
      canPop: searchedSignal == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && searchedSignal != null) _clearSearch();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(searchedSignal != null ? 'Search Result' : 'Trading Signals'),
        leading: searchedSignal != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _clearSearch,
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(
              marketStatus != null && marketStatus!['is_open'] ? Icons.wb_sunny : Icons.nights_stay,
              color: marketStatus != null && marketStatus!['is_open'] ? Colors.orange : Colors.blue,
            ),
            onPressed: _showMarketHoursDialog,
            tooltip: 'Market Hours',
          ),
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
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
    ));
  }

  Widget _buildSignalCard(Signal signal) {
    final isInWatchlist = inWatchlist[signal.ticker] ?? false;
    final pc = signal.percentChange;
    final isUp = (pc ?? 0) >= 0;
    const upColor = Color(0xFF16A34A);
    const downColor = Color(0xFFDC2626);
    final changeColor = isUp ? upColor : downColor;
    final cs = Theme.of(context).colorScheme;

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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
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
                        color: isInWatchlist ? cs.onSurface : cs.onSurface.withOpacity(0.35),
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
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                ),
              ],
              const SizedBox(height: 12),
              // Price + change row
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(signal.currentPrice, signal.currency),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (signal.isPremarket)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.purple.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Pre-market',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (pc != null && !signal.isPremarket)
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
                      _miniStat('MA50', _formatPrice(signal.ma50!, signal.currency)),
                    if (signal.ma200 != null)
                      _miniStat('MA200', _formatPrice(signal.ma200!, signal.currency)),
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
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withOpacity(0.4),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}