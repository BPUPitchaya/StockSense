import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/signal.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../theme.dart';

class StockComparisonScreen extends StatefulWidget {
  const StockComparisonScreen({super.key});

  @override
  State<StockComparisonScreen> createState() => _StockComparisonScreenState();
}

class _StockComparisonScreenState extends State<StockComparisonScreen> {
  List<Signal> availableStocks = [];
  List<Signal> filteredStocks = [];
  List<Signal> selectedStocks = [];
  bool isLoading = true;
  String? error;
  Map<String, dynamic>? comparisonData;
  final TextEditingController _searchController = TextEditingController();
  bool _hasSearchText = false;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/stocks/available'),
        headers: await ApiService._getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final signals = data.map((json) => Signal.fromJson(json)).toList();
        
        if (mounted) {
          setState(() {
            availableStocks = signals;
            filteredStocks = signals;
            isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load stocks');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Failed to load stocks';
          isLoading = false;
        });
      }
    }
  }

  void _filterStocks(String query) {
    setState(() {
      _hasSearchText = query.isNotEmpty;
      if (query.isEmpty) {
        filteredStocks = availableStocks;
      } else {
        filteredStocks = availableStocks
            .where((stock) => stock.ticker.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleStock(Signal stock) {
    setState(() {
      if (selectedStocks.contains(stock)) {
        selectedStocks.remove(stock);
      } else if (selectedStocks.length < 4) {
        selectedStocks.add(stock);
      }
    });
  }

  void _compareStocks() {
    if (selectedStocks.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 stocks to compare')),
      );
      return;
    }

    setState(() {
      comparisonData = {
        'stocks': selectedStocks,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Stocks'),
        actions: [
          if (selectedStocks.isNotEmpty)
            TextButton(
              onPressed: _compareStocks,
              child: Text(
                'Compare (${selectedStocks.length})',
                style: TextStyle(
                  color: isDark ? DarkColors.accent : AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadWatchlist,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : comparisonData != null
                  ? _buildComparisonView(isDark)
                  : _buildStockSelection(isDark),
    );
  }

  Widget _buildStockSelection(bool isDark) {
    if (availableStocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: isDark ? DarkColors.textFaint : AppColors.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'No stocks available',
              style: TextStyle(
                color: isDark ? DarkColors.textMuted : AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? DarkColors.surface : AppColors.surface,
            border: Border(
              bottom: BorderSide(color: isDark ? DarkColors.border : AppColors.border),
            ),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _filterStocks,
            decoration: InputDecoration(
              hintText: 'Search stocks...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasSearchText
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterStocks('');
                      },
                    )
                  : null,
            ),
          ),
        ),
        // Selection summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? DarkColors.surface : AppColors.surface,
            border: Border(
              bottom: BorderSide(color: isDark ? DarkColors.border : AppColors.border),
            ),
          ),
          child: Row(
            children: [
              Text(
                'Selected: ${selectedStocks.length}/4',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? DarkColors.text : AppColors.text,
                ),
              ),
              const Spacer(),
              if (selectedStocks.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedStocks.clear();
                    });
                  },
                  child: const Text('Clear All'),
                ),
            ],
          ),
        ),
        // Stock list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredStocks.length,
            itemBuilder: (context, index) {
              final stock = filteredStocks[index];
              final isSelected = selectedStocks.contains(stock);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? (isDark ? DarkColors.accent.withOpacity(0.1) : AppColors.accent.withOpacity(0.1))
                      : (isDark ? DarkColors.surface : AppColors.surface),
                  border: Border.all(
                    color: isSelected 
                        ? (isDark ? DarkColors.accent : AppColors.accent)
                        : (isDark ? DarkColors.border : AppColors.border),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? (isDark ? DarkColors.accent : AppColors.accent)
                          : (isDark ? DarkColors.surface : AppColors.bg),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected 
                            ? Colors.transparent
                            : (isDark ? DarkColors.border : AppColors.border),
                      ),
                    ),
                    child: Center(
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : Text(
                              stock.ticker.substring(0, 2),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDark ? DarkColors.text : AppColors.text,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                  title: Text(
                    stock.ticker,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? DarkColors.text : AppColors.text,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildSignalPill(stock.signal, isDark),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyService.format(stock.currentPrice),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? DarkColors.text : AppColors.text,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => _toggleStock(stock),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignalPill(String signal, bool isDark) {
    Color color;
    if (signal == 'Buy' || signal == 'Strong Buy') {
      color = isDark ? DarkColors.up : AppColors.up;
    } else if (signal == 'Sell' || signal == 'Strong Sell') {
      color = isDark ? DarkColors.down : AppColors.down;
    } else {
      color = isDark ? DarkColors.textMuted : AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        signal,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildComparisonView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.surface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? DarkColors.border : AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          comparisonData = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                    const Spacer(),
                    Text(
                      'Comparing ${selectedStocks.length} stocks',
                      style: TextStyle(
                        color: isDark ? DarkColors.textMuted : AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Stock headers
                Row(
                  children: [
                    const SizedBox(width: 100),
                    ...selectedStocks.map((stock) => Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? DarkColors.accent.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              stock.ticker,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDark ? DarkColors.accent : AppColors.accent,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              CurrencyService.format(stock.currentPrice),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? DarkColors.text : AppColors.text,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Comparison rows
          _buildComparisonRow('Signal', (stock) => stock.signal, isDark, isSignal: true),
          _buildComparisonRow('RSI', (stock) => stock.rsi?.toStringAsFixed(2) ?? 'N/A', isDark),
          _buildComparisonRow('MA50', (stock) => stock.ma50 != null ? CurrencyService.format(stock.ma50!) : 'N/A', isDark),
          _buildComparisonRow('MA200', (stock) => stock.ma200 != null ? CurrencyService.format(stock.ma200!) : 'N/A', isDark),
          _buildComparisonRow('Change %', (stock) => stock.percentChange != null ? '${stock.percentChange!.toStringAsFixed(2)}%' : 'N/A', isDark, isPercent: true),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, String Function(Signal) getValue, bool isDark, {bool isSignal = false, bool isPercent = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.surface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? DarkColors.border : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? DarkColors.textMuted : AppColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
          ...selectedStocks.map((stock) {
            final value = getValue(stock);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: isSignal
                    ? _buildSignalPill(value, isDark)
                    : isPercent
                        ? _buildPercentValue(value, isDark)
                        : Text(
                            value,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? DarkColors.text : AppColors.text,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPercentValue(String value, bool isDark) {
    if (value == 'N/A') {
      return Text(
        value,
        style: TextStyle(
          color: isDark ? DarkColors.textFaint : AppColors.textFaint,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      );
    }
    
    final isPositive = value.contains('-') == false;
    final color = isPositive 
        ? (isDark ? DarkColors.up : AppColors.up)
        : (isDark ? DarkColors.down : AppColors.down);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
