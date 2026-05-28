import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final TextEditingController _budgetController = TextEditingController();
  double _currentBudget = 0.0;
  Map<String, dynamic>? _recommendations;
  bool _isLoading = false;
  String? _errorMessage;
  // Snapshot of currency at the time recommendations were fetched
  String _snapCurrency = 'USD';
  String _snapSymbol = '\$';
  Map<String, dynamic> _snapRates = {};

  @override
  void initState() {
    super.initState();
    CurrencyService.load().then((_) {
      if (mounted) {
        setState(() {});
        _loadBudget();
      }
    });
  }

  Future<void> _loadBudget() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final budget = await ApiService.getBudget();
      final localAmount = CurrencyService.convert(budget);
      setState(() {
        _currentBudget = budget;
        _budgetController.text = (CurrencyService.currency == 'JPY' || CurrencyService.currency == 'KRW')
            ? localAmount.toStringAsFixed(0)
            : localAmount.toStringAsFixed(2);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _setBudget() async {
    final amount = double.tryParse(_budgetController.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid budget amount';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Ensure rates are fresh before converting
      await CurrencyService.load();
      final amountUsd = CurrencyService.toUsd(amount);
      await ApiService.setBudget(amountUsd);
      await _loadBudget();
      await _getRecommendations();
      // Snapshot currency state for display
      setState(() {
        _snapCurrency = CurrencyService.currency;
        _snapSymbol = CurrencyService.symbol;
        _snapRates = Map<String, dynamic>.from({});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _getRecommendations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final recommendations = await ApiService.getBudgetRecommendations();
      await CurrencyService.load();
      setState(() {
        _recommendations = recommendations;
        _snapCurrency = CurrencyService.currency;
        _snapSymbol = CurrencyService.symbol;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget & Recommendations'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ResponsiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Budget Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Investment Budget',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_currentBudget > 0)
                        Text(
                          'Current Budget: ${CurrencyService.format(_currentBudget)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        )
                      else
                        const Text(
                          'No budget set',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _budgetController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Enter weekly budget (${CurrencyService.currency})',
                          border: const OutlineInputBorder(),
                          prefixText: '${CurrencyService.symbol} ',
                          suffixText: CurrencyService.currency,
                          hintText: 'e.g. 100',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _setBudget,
                          child: _isLoading
                              ? const CircularProgressIndicator()
                              : const Text('Set Budget & Get Recommendations'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Error Message
              if (_errorMessage != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              // Recommendations Section
              if (_recommendations != null) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Based on your ${CurrencyService.format((_recommendations!['total_budget'] as num).toDouble())} budget',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildRecommendations(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Format a USD amount using the current user currency (rates are loaded before this is called)
  String _fmtBudget(double usdAmount) => CurrencyService.format(usdAmount);

  Widget _buildRecommendations() {
    final recommendations = _recommendations!;
    final stockRecommendations = recommendations['recommendations'] as List<dynamic>? ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Budget Allocation Recommendations',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Total Budget: ${_fmtBudget(((recommendations['total_budget'] ?? 0) as num).toDouble())}',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Total Allocated: ${_fmtBudget(((recommendations['total_allocated'] ?? 0) as num).toDouble())}',
              style: const TextStyle(fontSize: 16, color: Colors.green),
            ),
            Text(
              'Remaining: ${_fmtBudget(((recommendations['remaining_budget'] ?? 0) as num).toDouble())}',
              style: const TextStyle(fontSize: 16, color: Colors.orange),
            ),
            const SizedBox(height: 20),
            const Text(
              'Recommended Stocks:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...stockRecommendations.map((rec) {
              final stock = rec as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            stock['ticker'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stock['prediction'] == 'Strong Buy'
                                  ? Colors.green
                                  : Colors.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              stock['prediction'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Current Price: ${_fmtBudget((stock['current_price'] as num).toDouble())}'),
                      Text('Shares to Buy: ${stock['shares'].toStringAsFixed(4)}'),
                      Text(
                        'Amount to Invest: ${_fmtBudget((stock['actual_amount'] as num).toDouble())}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text('Allocation: ${stock['allocation_percentage'].toStringAsFixed(1)}%'),
                      Text('Confidence: ${stock['confidence'].toStringAsFixed(0)}%'),
                      Text('Score: ${stock['score'].toStringAsFixed(2)}'),
                      if (stock['potential_change'] != null)
                        Text(
                          'Est. Change: ${stock['potential_change'] > 0 ? '+' : ''}${stock['potential_change'].toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: stock['potential_change'] > 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Key Factors:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...(stock['factors'] as List<dynamic>)
                          .map((factor) => Text('• $factor')),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }
}
