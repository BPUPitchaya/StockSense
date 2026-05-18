import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen> {
  List<Map<String, dynamic>> predictions = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadPredictions();
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
          predictions = data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predictions'),
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
                        onPressed: _loadPredictions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPredictions,
                  child: ListView(
                    children: [
                      _buildGainersSection(),
                      _buildLosersSection(),
                      _buildHoldSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildGainersSection() {
    final gainers = predictions
        .where((p) => p['prediction'].toString().contains('Buy'))
        .toList();

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
    final losers = predictions
        .where((p) => p['prediction'].toString().contains('Sell'))
        .toList();

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
    final holds = predictions
        .where((p) => p['prediction'].toString() == 'Hold')
        .toList();

    if (holds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '⏸️ Hold / Neutral',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...holds.map((p) => _buildPredictionCard(p)).toList(),
      ],
    );
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
                    'Current: \$${prediction['current_price'].toStringAsFixed(2)}',
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
      builder: (context) => AlertDialog(
        title: Text('${prediction['ticker']} Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Prediction: ${prediction['prediction']}'),
              Text('Confidence: ${prediction['confidence']}%'),
              Text('Score: ${prediction['score'].toStringAsFixed(2)}'),
              Text('Trend Strength: ${prediction['trend_strength'] ?? 'Unknown'}'),
              if (prediction['adx'] != null)
                Text('ADX: ${prediction['adx'].toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              const Text(
                'All Factors:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...(prediction['factors'] as List).map((factor) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(factor)),
                      ],
                    ),
                  )),
            ],
          ),
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