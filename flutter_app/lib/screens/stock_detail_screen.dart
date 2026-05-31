import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/signal.dart';
import '../models/historical_data.dart';
import '../models/position.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../services/gemini_service.dart';
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
  String? _aiAnalysis;
  bool _isLoadingAi = false;
  DateTime? _buyDate;
  bool _useTotalAmount = false;

  // Chart line visibility toggles
  bool _showPrice = true;
  bool _showMA50 = true;
  bool _showMA200 = true;
  bool _showPrediction = true;
  
  // Historical predictions for accuracy tracking
  List<Map<String, dynamic>> _predictionHistory = [];
  
  // Projection data from backend
  Map<String, dynamic>? _projectionData;

  // Chart period selector
  String _selectedPeriod = '1y';
  final List<String> _periods = ['5d', '1mo', '3mo', '6mo', '1y', '2y', '5y', '10y', 'ytd', 'max'];
  final Map<String, String> _periodLabels = {
    '5d': '5 Days',
    '1mo': '1 Month',
    '3mo': '3 Months',
    '6mo': '6 Months',
    '1y': '1 Year',
    '2y': '2 Years',
    '5y': '5 Years',
    '10y': '10 Years',
    'ytd': 'YTD',
    'max': 'All Time',
  };

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
        return '$sym${price.toStringAsFixed(0)}';
      }
      return '$sym${price.toStringAsFixed(2)}';
    }
    // US stock — use user's currency symbol only
    final converted = CurrencyService.convert(price);
    if (CurrencyService.currency == 'KRW') {
      return '${converted.toStringAsFixed(0)}${CurrencyService.symbol}';
    }
    if (CurrencyService.currency == 'JPY') {
      return '${CurrencyService.symbol}${converted.toStringAsFixed(0)}';
    }
    return '${CurrencyService.symbol}${converted.toStringAsFixed(2)}';
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
        ApiService.getStockHistory(widget.signal.ticker, _selectedPeriod),
        ApiService.getStockInfo(widget.signal.ticker),
        ApiService.getPredictionHistory(widget.signal.ticker),
      ]);
      
      // Try to get projection, but don't fail if it errors
      Map<String, dynamic>? projectionData;
      try {
        projectionData = await ApiService.getProjection(widget.signal.ticker, _selectedPeriod);
      } catch (e) {
        print('Failed to load projection: $e');
        projectionData = null;
      }
      
      if (mounted) {
        setState(() {
          historicalData = results[0] as List<HistoricalData>;
          stockInfo = results[1] as Map<String, dynamic>;
          _predictionHistory = results[2] as List<Map<String, dynamic>>;
          _projectionData = projectionData;
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
                      const SizedBox(height: 16),
                      _buildAiAnalysisSection(),
                      const SizedBox(height: 24),
                      _buildPeriodSelector(),
                      const SizedBox(height: 16),
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

  Widget _buildIndicatorsCard() {
    final indicators = widget.signal.indicators!;
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Technical Indicators',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildIndicatorRow('Daily % Change', '${indicators['daily_percent_change']?.toStringAsFixed(2)}%'),
            _buildIndicatorRow('Price vs Open', '${indicators['price_vs_open']?.toStringAsFixed(2)}%'),
            _buildIndicatorRow('Price vs Prev Close', '${indicators['price_vs_previous_close']?.toStringAsFixed(2)}%'),
            _buildIndicatorRow('Position in Range', '${indicators['position_in_daily_range']?.toStringAsFixed(1)}%'),
            _buildIndicatorRow('MA50 Position', '${indicators['ma50_position']?.toStringAsFixed(2)}%'),
            _buildIndicatorRow('MA200 Position', '${indicators['ma200_position']?.toStringAsFixed(2)}%'),
            if (indicators['golden_death_cross'] != null)
              _buildIndicatorRow('Golden/Death Cross', indicators['golden_death_cross']),
            if (indicators['volume_confirmation'] != null)
              _buildIndicatorRow('Volume', indicators['volume_confirmation']),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
            if (widget.signal.indicators != null) _buildIndicatorsCard(),
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

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _periods.map((period) {
            final isSelected = _selectedPeriod == period;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedPeriod = period;
                  });
                  _loadData();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _periodLabels[period] ?? period,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
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

    // Use projection from backend if available, otherwise fall back to simple calculation
    final projectionSpots = <FlSpot>[];
    if (_projectionData != null && historicalData.isNotEmpty) {
      final projection = _projectionData!['projection'] as List<dynamic>?;
      if (projection != null && projection.isNotEmpty) {
        final lastIndex = historicalData.length - 1;
        final lastPrice = historicalData.last.close;
        // Start from the last actual data point for smooth connection
        projectionSpots.add(FlSpot(lastIndex.toDouble(), lastPrice));
        // Add projection points from backend
        for (var point in projection) {
          final day = point['day'] as int;
          final price = point['price'] as double;
          projectionSpots.add(FlSpot((lastIndex + day).toDouble(), price));
        }
      }
    } else if (historicalData.isNotEmpty && historicalData.length >= 5) {
      // Fallback to simple calculation if backend projection not available
      final lastPrice = historicalData.last.close;
      final lastIndex = historicalData.length - 1;
      // Determine trend based on signal
      final signalUpper = widget.signal.signal.toUpperCase();
      final trend = signalUpper.contains('BUY') ? 0.002 : signalUpper.contains('SELL') ? -0.002 : 0.0;
      // Daily volatility approximation
      final volatility = (rawMax - rawMin) / prices.length;
      // Projection length: proportional to data length (max 30 days, min 3 days)
      final projectionDays = (historicalData.length * 0.3).clamp(3, 30).toInt();
      // Start from the last actual data point for smooth connection
      projectionSpots.add(FlSpot(lastIndex.toDouble(), lastPrice));
      for (int i = 1; i <= projectionDays; i++) {
        final projectedPrice = lastPrice * (1 + (trend * i)) + (volatility * 0.1 * i);
        projectionSpots.add(FlSpot((lastIndex + i).toDouble(), projectedPrice));
      }
    }
    final hasProjection = projectionSpots.isNotEmpty;

    final List<LineChartBarData> lines = [
      if (_showPrice)
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
      if (hasMA200 && _showMA200)
        LineChartBarData(
          spots: ma200Spots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 1.5,
          dotData: FlDotData(show: false),
          dashArray: [6, 4],
        ),
      if (hasMA50 && _showMA50)
        LineChartBarData(
          spots: ma50Spots,
          isCurved: true,
          color: Colors.red,
          barWidth: 1.5,
          dotData: FlDotData(show: false),
          dashArray: [6, 4],
        ),
      if (hasProjection && _showPrediction)
        LineChartBarData(
          spots: projectionSpots,
          isCurved: true,
          color: Colors.purple,
          barWidth: 2,
          dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.x == projectionSpots.last.x),
          dashArray: [4, 4],
        ),
      // Historical prediction accuracy dots
      if (_predictionHistory.isNotEmpty && historicalData.isNotEmpty)
        ..._buildHistoricalPredictionDots(historicalData),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  Text(
                    'Price Chart (${_periodLabels[_selectedPeriod] ?? _selectedPeriod})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'AI Forecast',
                      style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            // Legend with toggleable items
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Wrap(
                spacing: 16,
                children: [
                  _buildLegendItem(Colors.blue, 'Price', _showPrice, () => setState(() => _showPrice = !_showPrice)),
                  if (hasMA50) _buildLegendItem(Colors.red, 'MA50', _showMA50, () => setState(() => _showMA50 = !_showMA50)),
                  if (hasMA200) _buildLegendItem(Colors.orange, 'MA200', _showMA200, () => setState(() => _showMA200 = !_showMA200)),
                  if (hasProjection) _buildLegendItem(Colors.purple, 'AI Forecast', _showPrediction, () => setState(() => _showPrediction = !_showPrediction)),
                  if (_predictionHistory.isNotEmpty) _buildAccuracyLegend(),
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
                        final colors = [Colors.blue, Colors.red, Colors.orange];
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

  Widget _buildLegendItem(Color color, String label, bool isVisible, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 2,
            color: isVisible ? color : Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isVisible ? Colors.grey.shade700 : Colors.grey.shade400,
              fontWeight: isVisible ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccuracyLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        const Text('Past Predictions', style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  List<LineChartBarData> _buildHistoricalPredictionDots(List<HistoricalData> historicalData) {
    final dots = <LineChartBarData>[];
    
    for (final pred in _predictionHistory) {
      try {
        final predDate = DateTime.parse(pred['prediction_date'] ?? '');
        final actualPrice = pred['actual_price'] as double?;
        final isCorrect = pred['is_correct'] as bool?;
        final currentPrice = pred['current_price'] as double?;
        
        // Find index in historical data closest to prediction date
        int closestIndex = -1;
        double minDiff = double.infinity;
        for (int i = 0; i < historicalData.length; i++) {
          final dataDate = DateTime.parse(historicalData[i].date);
          final diff = (dataDate.difference(predDate).inDays).abs();
          if (diff < minDiff) {
            minDiff = diff.toDouble();
            closestIndex = i;
          }
        }
        
        if (closestIndex >= 0 && closestIndex < historicalData.length) {
          // Dot color: green = correct prediction, red = wrong, grey = not checked yet
          Color dotColor = Colors.grey;
          if (isCorrect == true) dotColor = Colors.green;
          else if (isCorrect == false) dotColor = Colors.red;
          
          dots.add(LineChartBarData(
            spots: [FlSpot(closestIndex.toDouble(), historicalData[closestIndex].close)],
            isCurved: false,
            color: dotColor,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 6,
                color: dotColor,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
          ));
        }
      } catch (e) {
        // Skip invalid predictions
      }
    }
    
    return dots;
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

  String _cleanMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'#{1,3}\s*'), '')
        .replaceAll('**', '')
        .trim();
  }

  Future<void> _generateAiAnalysis() async {
    setState(() => _isLoadingAi = true);
    try {
      final metrics = <String, dynamic>{
        'current_price': widget.signal.currentPrice,
        'signal': widget.signal.signal,
        'rsi': widget.signal.rsi,
        'ma50': widget.signal.ma50,
        'ma200': widget.signal.ma200,
        'industry': stockInfo?['industry'],
        'market_cap': stockInfo?['market_cap'],
      };
      final result = await GeminiService.getStockEvaluation(widget.signal.ticker, metrics);
      if (mounted) setState(() => _aiAnalysis = result);
    } catch (e) {
      if (mounted) setState(() => _aiAnalysis = 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoadingAi = false);
    }
  }

  Widget _buildAiAnalysisSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final secondaryTextColor = theme.colorScheme.onSurface.withOpacity(0.6);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? Colors.deepPurple.withOpacity(0.15) : Colors.deepPurple.withOpacity(0.06),
            isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.withOpacity(0.06),
          ],
        ),
        border: Border.all(color: Colors.deepPurple.withOpacity(isDark ? 0.3 : 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'AI Analysis',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: textColor),
                ),
                const Spacer(),
                if (_aiAnalysis != null && !_isLoadingAi)
                  IconButton(
                    onPressed: _generateAiAnalysis,
                    icon: Icon(Icons.refresh, size: 18, color: textColor.withOpacity(0.7)),
                    tooltip: 'Regenerate',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_aiAnalysis == null && !_isLoadingAi) ...[
              Text(
                'Get a quick AI-powered breakdown of strengths, risks, and outlook for this stock.',
                style: TextStyle(fontSize: 13, color: secondaryTextColor, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generateAiAnalysis,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Generate AI Insights'),
                ),
              ),
            ] else if (_isLoadingAi)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text('Analyzing...', style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                  ],
                ),
              )
            else
              SelectableText(
                _cleanMarkdown(_aiAnalysis!),
                style: TextStyle(fontSize: 13.5, height: 1.55, color: textColor.withOpacity(0.9)),
              ),
          ],
        ),
      ),
    );
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