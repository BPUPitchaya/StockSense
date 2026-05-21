import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/signal.dart';
import '../models/historical_data.dart';
import '../services/api_service.dart';

class StockDetailScreen extends StatefulWidget {
  final Signal signal;

  const StockDetailScreen({super.key, required this.signal});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<HistoricalData> historicalData = [];
  Map<String, dynamic>? stockInfo;
  bool isLoading = true;
  String? error;
  List<String> personalWatchlist = [];
  bool isInWatchlist = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPersonalWatchlist();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getStockHistory(widget.signal.ticker, '3mo'),
        ApiService.getStockInfo(widget.signal.ticker),
      ]);
      
      if (mounted) {
        setState(() {
          historicalData = results[0] as List<HistoricalData>;
          stockInfo = results[1] as Map<String, dynamic>;
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

  Future<void> _loadPersonalWatchlist() async {
    try {
      final watchlist = await ApiService.getPersonalWatchlist();
      if (mounted) {
        setState(() {
          personalWatchlist = watchlist;
          isInWatchlist = watchlist.contains(widget.signal.ticker);
        });
      }
    } catch (e) {
      // Silently fail - personal watchlist is optional
    }
  }

  Future<void> _addToPersonalWatchlist() async {
    try {
      final validation = await ApiService.validateStock(widget.signal.ticker);
      
      if (!validation['valid']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot add: ${validation['reason']}')),
          );
        }
        return;
      }
      
      if (validation['is_etf']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ETFs may not work well with predictions')),
          );
        }
      }
      
      await ApiService.addToPersonalWatchlist(widget.signal.ticker);
      await _loadPersonalWatchlist();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${widget.signal.ticker} to personal watchlist')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _removeFromPersonalWatchlist() async {
    try {
      await ApiService.removeFromPersonalWatchlist(widget.signal.ticker);
      await _loadPersonalWatchlist();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${widget.signal.ticker} from personal watchlist')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.signal.ticker),
        actions: [
          IconButton(
            icon: Icon(isInWatchlist ? Icons.star : Icons.star_border),
            onPressed: isInWatchlist ? _removeFromPersonalWatchlist : _addToPersonalWatchlist,
            tooltip: isInWatchlist ? 'Remove from watchlist' : 'Add to watchlist',
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
                      Text('Error: $error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSignalCard(),
                      const SizedBox(height: 24),
                      _buildPriceChart(),
                      const SizedBox(height: 24),
                      _buildDetailsSection(),
                      const SizedBox(height: 24),
                      _buildStockInfoSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSignalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.signal.ticker,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Current Price: \$${widget.signal.currentPrice.toStringAsFixed(2)}'),
            if (widget.signal.ma50 != null)
              Text('50-day MA: \$${widget.signal.ma50!.toStringAsFixed(2)}'),
            if (widget.signal.ma200 != null)
              Text('200-day MA: \$${widget.signal.ma200!.toStringAsFixed(2)}'),
            if (widget.signal.rsi != null)
              Text('RSI: ${widget.signal.rsi!.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: _getSignalColor(widget.signal.signal),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.signal.signal,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceChart() {
    if (historicalData.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No historical data available'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Price Chart (3 Months)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '\$${value.toInt()}',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < historicalData.length) {
                            return Text(
                              historicalData[value.toInt()].date.substring(5),
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                        interval: historicalData.length > 30 ? 5 : 1,
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: historicalData.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.close,
                        );
                      }).toList(),
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Date: ${widget.signal.date}'),
            if (historicalData.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Data Points: ${historicalData.length}'),
              Text('Price Range: \$${historicalData.map((d) => d.low).reduce((a, b) => a < b ? a : b).toStringAsFixed(2)} - \$${historicalData.map((d) => d.high).reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockInfoSection() {
    if (stockInfo == null) {
      return const SizedBox.shrink();
    }

    final info = stockInfo!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stock Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Market Cap', _formatNumber(info['market_cap'] * 1e6)),
            _buildInfoRow('P/E Ratio', info['pe_ratio']?.toStringAsFixed(2) ?? 'N/A'),
            _buildInfoRow('Dividend Yield', info['dividend_yield'] != null ? '${(info['dividend_yield'] * 100).toStringAsFixed(2)}%' : 'N/A'),
            _buildInfoRow('Dividend Rate', '\$${info['dividend_rate']?.toStringAsFixed(2) ?? 'N/A'}'),
            _buildInfoRow('Beta', info['beta']?.toStringAsFixed(2) ?? 'N/A'),
            _buildInfoRow('EPS', '\$${info['eps']?.toStringAsFixed(2) ?? 'N/A'}'),
            _buildInfoRow('Avg Volume', _formatNumber(info['avg_volume'])),
            _buildInfoRow('52-Week High', '\$${info['52_week_high']?.toStringAsFixed(2) ?? 'N/A'}'),
            _buildInfoRow('52-Week Low', '\$${info['52_week_low']?.toStringAsFixed(2) ?? 'N/A'}'),
            if (info['profit_margin'] != null)
              _buildInfoRow('Profit Margin', '${(info['profit_margin'] * 100).toStringAsFixed(2)}%'),
            if (info['revenue'] != null)
              _buildInfoRow('Revenue', _formatNumber(info['revenue'])),
            if (info['industry'] != null)
              _buildInfoRow('Industry', info['industry']),
            if (info['sector'] != null)
              _buildInfoRow('Sector', info['sector']),
            if (info['description'] != null)
              _buildInfoRow('Description', info['description']),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return 'N/A';
    
    double numValue = value is int ? value.toDouble() : value;
    
    // Finnhub returns market cap in millions, so multiply by 1e6
    if (numValue < 1e3) return '\$${numValue.toStringAsFixed(2)}';
    if (numValue < 1e6) return '\$${(numValue / 1e3).toStringAsFixed(2)}K';
    if (numValue < 1e9) return '\$${(numValue / 1e6).toStringAsFixed(2)}M';
    if (numValue < 1e12) return '\$${(numValue / 1e9).toStringAsFixed(2)}B';
    return '\$${(numValue / 1e12).toStringAsFixed(2)}T';
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
}