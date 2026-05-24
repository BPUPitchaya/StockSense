import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/signal.dart';
import '../models/historical_data.dart';
import '../models/position.dart';
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
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  DateTime? _buyDate;
  bool _useTotalAmount = false;

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
        return; // Don't add if invalid
      }
      
      if (validation['is_etf']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ETFs are not supported for predictions')),
          );
        }
        return; // Don't add if ETF
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
      // Force state update immediately
      if (mounted) {
        setState(() {
          isInWatchlist = false;
          personalWatchlist.remove(widget.signal.ticker);
        });
      }
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

  void _showAddToPortfolioDialog() {
    _buyDate = DateTime.now();
    _quantityController.clear();
    _buyPriceController.clear();
    _totalAmountController.clear();
    _useTotalAmount = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add ${widget.signal.ticker} to Portfolio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Enter by: '),
                  Switch(
                    value: _useTotalAmount,
                    onChanged: (value) {
                      setState(() {
                        _useTotalAmount = value;
                      });
                      setDialogState(() {
                        _useTotalAmount = value;
                      });
                    },
                  ),
                  Text(_useTotalAmount ? 'Total Amount' : 'Quantity'),
                ],
              ),
              const SizedBox(height: 16),
              if (_useTotalAmount) ...[
                TextField(
                  controller: _totalAmountController,
                  decoration: const InputDecoration(
                    labelText: 'Total Investment Amount',
                    hintText: 'Total amount spent (e.g., 1000)',
                    border: OutlineInputBorder(),
                    prefixText: '\$',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final total = double.tryParse(value);
                    final price = double.tryParse(_buyPriceController.text);
                    if (total != null && price != null && price > 0) {
                      final calculatedQuantity = total / price;
                      _quantityController.text = calculatedQuantity.toStringAsFixed(2);
                    }
                  },
                ),
                const SizedBox(height: 16),
              ] else ...[
                TextField(
                  controller: _quantityController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    hintText: 'Number of shares',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _buyPriceController,
                decoration: const InputDecoration(
                  labelText: 'Buy Price',
                  hintText: 'Price per share',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  if (_useTotalAmount) {
                    final total = double.tryParse(_totalAmountController.text);
                    final price = double.tryParse(value);
                    if (total != null && price != null && price > 0) {
                      final calculatedQuantity = total / price;
                      _quantityController.text = calculatedQuantity.toStringAsFixed(2);
                    }
                  }
                },
              ),
              if (_useTotalAmount) ...[
                const SizedBox(height: 8),
                Text(
                  'Calculated Quantity: ${_quantityController.text} shares',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                title: Text('Buy Date: ${_buyDate.toString().split(' ')[0]}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _buyDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _buyDate = picked;
                    });
                    setDialogState(() {
                      _buyDate = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _addToPortfolio,
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToPortfolio() async {
    final quantity = double.tryParse(_quantityController.text);
    final buyPrice = double.tryParse(_buyPriceController.text);
    
    if (quantity == null || quantity <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid quantity')),
        );
      }
      return;
    }
    
    if (buyPrice == null || buyPrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid buy price')),
        );
      }
      return;
    }
    
    if (_buyDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a buy date')),
        );
      }
      return;
    }
    
    try {
      final position = Position(
        ticker: widget.signal.ticker,
        buyPrice: buyPrice,
        quantity: quantity,
        date: _buyDate.toString().split(' ')[0],
      );
      
      await ApiService.addPosition(position.toJson());
      
      Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${widget.signal.ticker} to portfolio')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add to portfolio: ${e.toString()}')),
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
            icon: Icon(
              isInWatchlist ? Icons.star : Icons.star_border,
              color: isInWatchlist ? Colors.black : null,
            ),
            onPressed: isInWatchlist ? _removeFromPersonalWatchlist : _addToPersonalWatchlist,
            tooltip: isInWatchlist ? 'Remove from watchlist' : 'Add to watchlist',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showAddToPortfolioDialog,
            tooltip: 'Add to portfolio',
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
            if (info['market_cap'] != null)
              _buildInfoRow('Market Cap', _formatNumber((info['market_cap'] as num) * 1e6)),
            _buildInfoRow('P/E Ratio', info['pe_ratio']?.toStringAsFixed(2) ?? 'N/A'),
            _buildInfoRow('Dividend Yield', info['dividend_yield'] != null ? '${((info['dividend_yield'] as num) * 100).toStringAsFixed(2)}%' : 'N/A'),
            _buildInfoRow('Dividend Rate', '\$${info['dividend_rate']?.toStringAsFixed(2) ?? 'N/A'}'),
            _buildInfoRow('Beta', info['beta']?.toStringAsFixed(2) ?? 'N/A'),
            _buildInfoRow('EPS', '\$${info['eps']?.toStringAsFixed(2) ?? 'N/A'}'),
            if (info['avg_volume'] != null)
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