import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/signal.dart';
import '../models/historical_data.dart';
import '../models/position.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';

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

  /// Currency symbols for native formatting
  static const _currencySymbols = {
    'USD': '\$', 'AUD': 'A\$', 'NZD': 'NZ\$', 'GBP': '£',
    'EUR': '€', 'JPY': '¥', 'CNY': '¥', 'CAD': 'C\$',
    'HKD': 'HK\$', 'SGD': 'S\$', 'KRW': '₩', 'INR': '₹',
  };

  /// Format a price in the stock's native currency (no conversion).
  /// Falls back to user's CurrencyService if currency unknown.
  String _fmtPrice(double price) {
    final nativeCurrency = stockInfo?['currency'] as String?;
    if (nativeCurrency != null && nativeCurrency != 'USD') {
      final sym = _currencySymbols[nativeCurrency] ?? nativeCurrency;
      if (nativeCurrency == 'JPY' || nativeCurrency == 'KRW') {
        return '$sym${price.toStringAsFixed(0)} $nativeCurrency';
      }
      return '$sym${price.toStringAsFixed(2)} $nativeCurrency';
    }
    // US stock — append user's currency code
    final code = CurrencyService.currency;
    return '${CurrencyService.format(price)} $code';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPersonalWatchlist();
    CurrencyService.load().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getStockHistory(widget.signal.ticker, '1y'),
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
        title: Text(stockInfo?['name'] ?? widget.signal.ticker),
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
              : ResponsiveBody(
                  child: SingleChildScrollView(
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
                      const SizedBox(height: 24),
                      _buildDescriptionSection(),
                    ],
                  ),
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
              stockInfo?['name'] ?? widget.signal.ticker,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (stockInfo?['name'] != null)
              Text(
                widget.signal.ticker,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 16),
            Text('Current Price: ${_fmtPrice(widget.signal.currentPrice)}'),
            if (stockInfo != null && stockInfo!['unit'] != null)
              Text('Unit: ${stockInfo!['unit']}'),
            if (widget.signal.ma50 != null)
              Text('50-day MA: ${_fmtPrice(widget.signal.ma50!)}'),
            if (widget.signal.ma200 != null)
              Text('200-day MA: ${_fmtPrice(widget.signal.ma200!)}'),
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

    final prices = historicalData.map((d) => d.close).toList();
    final rawMin = prices.reduce((a, b) => a < b ? a : b);
    final rawMax = prices.reduce((a, b) => a > b ? a : b);
    final padding = (rawMax - rawMin) * 0.1;
    final minY = rawMin - padding;
    final maxY = rawMax + padding;
    final yRange = maxY - minY;

    // Show ~4 evenly spaced labels on Y axis
    final yInterval = yRange / 4;

    // Show ~5 date labels across the bottom
    final xInterval = (historicalData.length / 5).ceilToDouble();

    // Compute rolling MAs from actual historical closes
    List<FlSpot> rollingMA(int period) {
      if (historicalData.length < period) return [];
      final spots = <FlSpot>[];
      double windowSum = historicalData
          .sublist(0, period)
          .fold(0.0, (s, d) => s + d.close);
      spots.add(FlSpot((period - 1).toDouble(), windowSum / period));
      for (int i = period; i < historicalData.length; i++) {
        windowSum += historicalData[i].close - historicalData[i - period].close;
        spots.add(FlSpot(i.toDouble(), windowSum / period));
      }
      return spots;
    }

    final ma50Spots = rollingMA(50);
    final ma200Spots = rollingMA(200);
    final hasMA50 = ma50Spots.isNotEmpty;
    final hasMA200 = ma200Spots.isNotEmpty;

    final List<LineChartBarData> lines = [
      LineChartBarData(
        spots: historicalData.asMap().entries.map((e) =>
            FlSpot(e.key.toDouble(), e.value.close)).toList(),
        isCurved: true,
        color: Colors.blue,
        barWidth: 2,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: Colors.blue.withOpacity(0.08),
        ),
      ),
      if (hasMA50)
        LineChartBarData(
          spots: ma50Spots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 1.5,
          dotData: FlDotData(show: false),
          dashArray: [6, 4],
        ),
      if (hasMA200)
        LineChartBarData(
          spots: ma200Spots,
          isCurved: true,
          color: Colors.red,
          barWidth: 1.5,
          dotData: FlDotData(show: false),
          dashArray: [6, 4],
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: const Text(
                'Price Chart (1 Year)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Legend
            if (hasMA50 || hasMA200)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: Wrap(
                  spacing: 16,
                  children: [
                    _buildLegendItem(Colors.blue, 'Price'),
                    if (hasMA50) _buildLegendItem(Colors.orange, 'MA50'),
                    if (hasMA200) _buildLegendItem(Colors.red, 'MA200'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          final label = _fmtPrice(value);
                          return Text(label, style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: xInterval,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= historicalData.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              historicalData[i].date.substring(5),
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      left: BorderSide(color: Colors.grey.withOpacity(0.3)),
                    ),
                  ),
                  lineBarsData: lines,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final colors = [Colors.blue, Colors.orange, Colors.red];
                        final labels = ['Price', 'MA50', 'MA200'];
                        final idx = s.barIndex.clamp(0, 2);
                        return LineTooltipItem(
                          '${labels[idx]}: ${_fmtPrice(s.y)}',
                          TextStyle(color: colors[idx], fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
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
              Text('Price Range: ${_fmtPrice(historicalData.map((d) => d.low).reduce((a, b) => a < b ? a : b))} - ${_fmtPrice(historicalData.map((d) => d.high).reduce((a, b) => a > b ? a : b))}'),
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
            // Price data — always available from Finnhub quote
            _buildInfoRow('Open', _fmtPrice((info['open'] as num?)?.toDouble() ?? 0)),
            _buildInfoRow('Prev Close', _fmtPrice((info['previous_close'] as num?)?.toDouble() ?? 0)),
            _buildInfoRow("Day's High", _fmtPrice((info['high'] as num?)?.toDouble() ?? 0)),
            _buildInfoRow("Day's Low", _fmtPrice((info['low'] as num?)?.toDouble() ?? 0)),
            // Technical indicators — computed from 1y history, cached
            if (info['ma50'] != null)
              _buildInfoRow('MA 50', _fmtPrice((info['ma50'] as num).toDouble())),
            if (info['ma200'] != null)
              _buildInfoRow('MA 200', _fmtPrice((info['ma200'] as num).toDouble())),
            if (info['volume_ratio'] != null)
              _buildInfoRow('Volume vs Avg', '${(info['volume_ratio'] as num).toStringAsFixed(2)}x'),
            // Company info — always available from Finnhub profile
            if (info['market_cap'] != null)
              _buildInfoRow('Market Cap', _formatNumber((info['market_cap'] as num) * 1e6)),
            if (info['exchange'] != null)
              _buildInfoRow('Exchange', info['exchange']),
            if (info['country'] != null)
              _buildInfoRow('Country', info['country']),
            if (info['industry'] != null)
              _buildInfoRow('Industry', info['industry']),
            if (info['sector'] != null)
              _buildInfoRow('Sector', info['sector']),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(_getAboutDescription()),
          ],
        ),
      ),
    );
  }

  String _getAboutDescription() {
    final ticker = widget.signal.ticker;
    final descriptions = {
      'GC=F': 'Gold (GC=F) is a precious metal commodity traded on futures markets. Price is per troy ounce (31.1035g). Gold is often used as a store of value and hedge against inflation. Thai gold price is typically quoted per baht weight (15.2g).',
      'SI=F': 'Silver (SI=F) is a precious metal commodity traded on futures markets. Price is per troy ounce (31.1035g). Silver has both industrial and investment demand.',
      'GLD': 'GLD (SPDR Gold Shares) is an ETF that tracks the price of gold. Each share represents approximately 1/10th of an ounce of gold.',
      'SLV': 'SLV (iShares Silver Trust) is an ETF that tracks the price of silver. Each share represents approximately 1 ounce of silver.',
      'IAU': 'IAU (iShares Gold Trust) is an ETF that tracks the price of gold. Each share represents approximately 1/100th of an ounce of gold.',
    };
    return descriptions[ticker] ?? 'This is a stock/ETF that can be traded on major exchanges. Prices are shown in USD. Please research this security before investing.';
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
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
}