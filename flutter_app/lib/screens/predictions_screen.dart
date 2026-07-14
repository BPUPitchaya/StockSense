import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen> {
  Map<String, dynamic> predictionsData = {};
  List<Map<String, dynamic>> gainers = [];
  List<Map<String, dynamic>> losers = [];
  bool isLoading = true;
  String? error;
  List<String> personalWatchlist = [];
  bool isLoadingWatchlist = false;
  TextEditingController tickerController = TextEditingController();
  Map<String, dynamic> accuracyData = {};
  bool isLoadingAccuracy = true;

  @override
  void initState() {
    super.initState();
    _loadPredictions();
    _loadPersonalWatchlist();
    _loadAccuracy();
    CurrencyService.load().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> _loadAccuracy() async {
    try {
      final data = await ApiService.getPredictionAccuracy();
      if (mounted) {
        setState(() {
          accuracyData = data;
          isLoadingAccuracy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingAccuracy = false;
        });
      }
    }
  }

  Future<void> _loadPredictions() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final data = await ApiService.getPredictions();
      if (mounted) {
        setState(() {
          predictionsData = data;
          gainers = (data['gainers'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
          losers = (data['losers'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPersonalWatchlist() async {
    setState(() {
      isLoadingWatchlist = true;
    });

    try {
      final watchlist = await ApiService.getPersonalWatchlist();
      if (mounted) {
        setState(() {
          personalWatchlist = watchlist;
          isLoadingWatchlist = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingWatchlist = false;
        });
      }
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
      // Validate stock before adding
      final validation = await ApiService.validateStock(ticker);
      
      if (validation['is_etf'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$ticker" is an ETF and is not supported for predictions.')),
          );
        }
        return;
      }

      if (!validation['valid']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$ticker" is not a valid stock ticker. Please check and try again.')),
          );
        }
        return;
      }
      
      await ApiService.addToPersonalWatchlist(ticker);
      await _loadPersonalWatchlist();
      await _loadPredictions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add $ticker. Please check the ticker and try again.')),
        );
      }
    }
  }

  Future<void> _removeFromPersonalWatchlist(String ticker) async {
    try {
      await ApiService.removeFromPersonalWatchlist(ticker);
      await _loadPersonalWatchlist();
      await _loadPredictions(); // Reload predictions to use updated watchlist
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove $ticker. Please try again.')),
        );
      }
    }
  }

  void _showAddToWatchlistDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Personal Watchlist'),
        content: TextField(
          controller: tickerController,
          decoration: const InputDecoration(
            hintText: 'Enter stock ticker (e.g., AAPL)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              tickerController.clear();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final ticker = tickerController.text.trim().toUpperCase();
              if (ticker.isNotEmpty) {
                Navigator.pop(context);
                _addToPersonalWatchlist(ticker);
                tickerController.clear();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predictions'),
      ),
      body: ResponsiveBody(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? ListView(
                    children: [
                      // Still show watchlist so user can remove bad tickers
                      _buildPersonalWatchlistSection(),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange),
                            const SizedBox(height: 12),
                            const Text('Could not load predictions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            const Text('A ticker in your watchlist may be invalid.\nRemove it above and retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _loadPredictions,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadPredictions();
                      await _loadAccuracy();
                    },
                    child: ListView(
                      children: [
                        _buildAccuracyDashboard(),
                        _buildPersonalWatchlistSection(),
                        _buildGainersSection(),
                        _buildLosersSection(),
                        _buildHoldSection(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildAccuracyDashboard() {
    if (isLoadingAccuracy) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final totalPredictions = accuracyData['total_predictions'] ?? 0;
    final checkedPredictions = accuracyData['checked_predictions'] ?? 0;
    final correctCount = accuracyData['correct_direction_count'] ?? 0;
    final directionAccuracy = (accuracyData['direction_accuracy'] ?? 0.0).toDouble();
    final avgAccuracy = (accuracyData['average_accuracy_percent'] ?? 0.0).toDouble();
    final byTicker = (accuracyData['by_ticker'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];

    if (checkedPredictions == 0) {
      return Card(
        margin: const EdgeInsets.all(16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.insights, size: 40, color: Colors.blue.shade300),
              const SizedBox(height: 12),
              const Text(
                'AI Accuracy Tracking',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$totalPredictions predictions are being tracked.\nAccuracy results will appear after the 10-day evaluation period.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: totalPredictions > 0 ? 1.0 : 0.0,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Text(
                '$totalPredictions predictions awaiting evaluation',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'AI Prediction Accuracy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildAccuracyMetric(
                    'Direction Accuracy',
                    '${directionAccuracy.toStringAsFixed(1)}%',
                    _getAccuracyColor(directionAccuracy),
                    '$correctCount / $checkedPredictions correct',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAccuracyMetric(
                    'Price Accuracy',
                    '${avgAccuracy.toStringAsFixed(1)}%',
                    _getAccuracyColor(avgAccuracy),
                    'Avg. closeness',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: directionAccuracy / 100,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(_getAccuracyColor(directionAccuracy)),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Based on $checkedPredictions evaluated predictions out of $totalPredictions total',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            if (byTicker.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Accuracy by Stock',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...byTicker.take(5).map((t) => _buildTickerAccuracyRow(t)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccuracyMetric(String label, String value, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTickerAccuracyRow(Map<String, dynamic> tickerData) {
    final ticker = tickerData['ticker'] ?? '';
    final total = tickerData['total_predictions'] ?? 0;
    final correct = tickerData['correct_predictions'] ?? 0;
    final accuracy = (tickerData['accuracy_percent'] ?? 0.0).toDouble();
    final color = _getAccuracyColor(accuracy);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              ticker,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: accuracy / 100,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              '${accuracy.toStringAsFixed(0)}%',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              '$correct/$total',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= 70) return Colors.green;
    if (accuracy >= 50) return Colors.orange;
    return Colors.red;
  }

  Widget _buildPersonalWatchlistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '⭐ My Watchlist  (${personalWatchlist.length}/5)',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: personalWatchlist.length >= 5 ? null : _showAddToWatchlistDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        if (isLoadingWatchlist)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (personalWatchlist.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No stocks in personal watchlist. Add stocks to get personalized predictions.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: personalWatchlist.map((ticker) => Chip(
                label: Text(ticker),
                deleteIcon: const Icon(Icons.close),
                onDeleted: () => _removeFromPersonalWatchlist(ticker),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade700
                    : Colors.blue.shade100,
                labelStyle: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              )).toList(),
            ),
          ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildGainersSection() {
    if (gainers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '📈 Potential Gainers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ),
        ...gainers.map((p) => _buildPredictionCard(p)).toList(),
      ],
    );
  }

  Widget _buildLosersSection() {
    if (losers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '📉 Potential Losers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ),
        ...losers.map((p) => _buildPredictionCard(p)).toList(),
      ],
    );
  }

  Widget _buildHoldSection() {
    return const SizedBox.shrink(); // No longer needed with new API format
  }

  Widget _buildPredictionCard(Map<String, dynamic> prediction) {
    final predictionText = prediction['prediction'].toString();
    final potentialChange = (prediction['potential_change'] as num).toDouble();
    final confidence = (prediction['confidence'] as num).toInt();
    final trendStrength = prediction['trend_strength']?.toString() ?? 'Unknown';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: InkWell(
        onTap: () => _showPredictionDetails(prediction),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    prediction['ticker'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getPredictionColor(predictionText),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      predictionText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.attach_money, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Current: ${CurrencyService.format((prediction['current_price'] as num).toDouble())}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    potentialChange > 0 ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: potentialChange > 0 ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Potential: ${potentialChange > 0 ? '+' : ''}${potentialChange.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 15,
                      color: potentialChange > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confidence',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: confidence / 100,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getConfidenceColor(confidence),
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '$confidence%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _getTrendStrengthIcon(trendStrength),
                    size: 16,
                    color: _getTrendStrengthColor(trendStrength),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Trend: $trendStrength',
                    style: TextStyle(
                      fontSize: 13,
                      color: _getTrendStrengthColor(trendStrength),
                    ),
                  ),
                ],
              ),
              if (prediction['factors'] != null && prediction['factors'].isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Key Factors:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                ...(prediction['factors'] as List).take(3).map((factor) => Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontSize: 13)),
                          Expanded(
                            child: Text(
                              factor,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )),
                if ((prediction['factors'] as List).length > 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      '+ ${(prediction['factors'] as List).length - 3} more',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _buildTimeframeConfirmation(prediction),
            ],
          ),
        ),
      ),
    );
  }

  Color _getPredictionColor(String prediction) {
    switch (prediction.toUpperCase()) {
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

  Color _getConfidenceColor(int confidence) {
    if (confidence >= 75) return Colors.green;
    if (confidence >= 50) return Colors.orange;
    return Colors.red;
  }

  IconData _getTrendStrengthIcon(String strength) {
    switch (strength.toLowerCase()) {
      case 'strong':
        return Icons.trending_up;
      case 'moderate':
        return Icons.trending_flat;
      case 'weak':
        return Icons.trending_down;
      default:
        return Icons.help_outline;
    }
  }

  Color _getTrendStrengthColor(String strength) {
    switch (strength.toLowerCase()) {
      case 'strong':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'weak':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showPredictionDetails(Map<String, dynamic> prediction) {
    showDialog(
      context: context,
      builder: (context) => _PredictionDetailDialog(prediction: prediction),
    );
  }

  Widget _buildTimeframeConfirmation(Map<String, dynamic> prediction) {
    final timeframeAnalysis = prediction['timeframe_analysis'] as Map<String, dynamic>?;
    if (timeframeAnalysis == null) {
      return const SizedBox.shrink();
    }

    final daily = timeframeAnalysis['daily'] as Map<String, dynamic>?;
    final weekly = timeframeAnalysis['weekly'] as Map<String, dynamic>?;
    final monthly = timeframeAnalysis['monthly'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeframe Confirmation',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTimeframeBadge('Daily', daily?['signal']),
              _buildTimeframeBadge('Weekly', weekly?['signal']),
              _buildTimeframeBadge('Monthly', monthly?['signal']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeBadge(String label, String? signal) {
    Color color;
    IconData icon;

    switch (signal) {
      case 'bullish':
        color = Colors.green;
        icon = Icons.trending_up;
        break;
      case 'bearish':
        color = Colors.red;
        icon = Icons.trending_down;
        break;
      case 'neutral':
        color = Colors.grey;
        icon = Icons.trending_flat;
        break;
      default:
        color = Colors.grey.shade400;
        icon = Icons.help_outline;
    }

    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _PredictionDetailDialog extends StatefulWidget {
  final Map<String, dynamic> prediction;

  const _PredictionDetailDialog({required this.prediction});

  @override
  State<_PredictionDetailDialog> createState() => _PredictionDetailDialogState();
}

class _PredictionDetailDialogState extends State<_PredictionDetailDialog> {
  List<Map<String, dynamic>> history = [];
  bool isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final ticker = widget.prediction['ticker'];
      final data = await ApiService.getPredictionHistory(ticker);
      if (mounted) {
        setState(() {
          history = data;
          isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingHistory = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prediction = widget.prediction;
    final predictionText = prediction['prediction'].toString();
    final confidence = (prediction['confidence'] as num).toInt();
    final trendStrength = prediction['trend_strength']?.toString() ?? 'Unknown';
    final currentPrice = (prediction['current_price'] as num).toDouble();
    final potentialChange = (prediction['potential_change'] as num).toDouble();

    // Calculate predicted price (2% over 10 days in predicted direction)
    final predictedPrice = potentialChange > 0
        ? currentPrice * 1.02
        : potentialChange < 0
            ? currentPrice * 0.98
            : currentPrice;

    return AlertDialog(
      title: Text('${prediction['ticker']} Details'),
      content: SingleChildScrollView(
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            // Current prediction summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Signal', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getPredictionColor(predictionText),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          predictionText,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildPriceRow('Current Price', CurrencyService.format(currentPrice), Colors.grey.shade700),
                  const SizedBox(height: 6),
                  _buildPriceRow(
                    'Predicted Price (10d)',
                    CurrencyService.format(predictedPrice),
                    potentialChange > 0 ? Colors.green : potentialChange < 0 ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(height: 6),
                  _buildPriceRow(
                    'Expected Change',
                    '${potentialChange > 0 ? '+' : ''}${potentialChange.toStringAsFixed(1)}%',
                    potentialChange > 0 ? Colors.green : potentialChange < 0 ? Colors.red : Colors.grey,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Confidence: $confidence%'),
            Text('Score: ${prediction['score'].toStringAsFixed(2)}'),
            Text('Trend Strength: $trendStrength'),
            if (prediction['adx'] != null)
              Text('ADX: ${prediction['adx'].toStringAsFixed(2)}'),

            // Prediction track record
            const SizedBox(height: 20),
            const Text(
              'Prediction Track Record',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            if (isLoadingHistory)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No past predictions evaluated yet for this stock.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              )
            else
              ...history.take(5).map((h) => _buildHistoryRow(h)),

            // All factors
            const SizedBox(height: 16),
            const Text(
              'All Factors:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            ...(prediction['factors'] as List).map((factor) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(factor, style: const TextStyle(color: Colors.black87))),
                    ],
                  ),
                )),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPriceRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> h) {
    final hasResult = h['actual_price'] != null;
    final predictedDir = h['predicted_direction'] ?? 'flat';
    final isCorrect = h['is_correct'] == true;
    final accuracy = (h['accuracy_percent'] as num?)?.toDouble();
    final currentPrice = (h['current_price'] as num?)?.toDouble();
    final actualPrice = (h['actual_price'] as num?)?.toDouble();

    // Calculate predicted price
    final predictedPrice = currentPrice != null
        ? predictedDir == 'up'
            ? currentPrice * 1.02
            : predictedDir == 'down'
                ? currentPrice * 0.98
                : currentPrice
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasResult
            ? (isCorrect ? Colors.green.shade50 : Colors.red.shade50)
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasResult
              ? (isCorrect ? Colors.green.shade200 : Colors.red.shade200)
              : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Predicted: ${predictedDir.toUpperCase()}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              if (hasResult)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCorrect ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isCorrect ? 'CORRECT' : 'WRONG',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PENDING',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (currentPrice != null && predictedPrice != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Was: ${CurrencyService.format(currentPrice)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Text(
                  'Target: ${CurrencyService.format(predictedPrice)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          if (hasResult && actualPrice != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Actual: ${CurrencyService.format(actualPrice)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                if (accuracy != null)
                  Text(
                    'Accuracy: ${accuracy.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accuracy >= 70 ? Colors.green : accuracy >= 50 ? Colors.orange : Colors.red,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getPredictionColor(String prediction) {
    switch (prediction.toUpperCase()) {
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