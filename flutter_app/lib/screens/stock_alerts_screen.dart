import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StockAlertsScreen extends StatefulWidget {
  const StockAlertsScreen({super.key});

  @override
  State<StockAlertsScreen> createState() => _StockAlertsScreenState();
}

class _StockAlertsScreenState extends State<StockAlertsScreen> {
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getStockAlerts();
      setState(() {
        _alerts = data['alerts'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load alerts: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAlert(int alertId) async {
    try {
      await ApiService.deleteStockAlert(alertId);
      _loadAlerts();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert deleted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete alert: $e')),
      );
    }
  }

  void _showAddAlertDialog() {
    final tickerController = TextEditingController();
    final priceController = TextEditingController();
    String condition = 'above';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Price Alert'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tickerController,
                decoration: const InputDecoration(
                  labelText: 'Ticker Symbol',
                  hintText: 'e.g., AAPL',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Target Price',
                  hintText: 'e.g., 150.00',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('Alert when price is:'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'above',
                    label: Text('Above'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: 'below',
                    label: Text('Below'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {condition},
                onSelectionChanged: (Set<String> newSelection) {
                  setDialogState(() {
                    condition = newSelection.first;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ticker = tickerController.text.trim();
                final price = double.tryParse(priceController.text);
                
                if (ticker.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a ticker')),
                  );
                  return;
                }
                if (price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid price')),
                  );
                  return;
                }
                
                Navigator.pop(context);
                try {
                  await ApiService.createStockAlert(ticker, price, condition);
                  _loadAlerts();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alert created successfully')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create alert: $e')),
                  );
                }
              },
              child: const Text('Create Alert'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Price Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddAlertDialog,
            tooltip: 'Add Alert',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAlerts,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _alerts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No price alerts set', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _showAddAlertDialog,
                            child: const Text('Add your first alert'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) {
                        final alert = _alerts[index];
                        final isTriggered = alert['is_triggered'] ?? false;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isTriggered ? theme.colorScheme.errorContainer.withOpacity(0.3) : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: alert['condition'] == 'above' 
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              child: Icon(
                                alert['condition'] == 'above' 
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: alert['condition'] == 'above' 
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            title: Text(
                              alert['ticker'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: isTriggered ? FontWeight.normal : FontWeight.bold,
                                decoration: isTriggered ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Target: \$${alert['target_price']?.toStringAsFixed(2) ?? '0.00'}'),
                                Text(
                                  isTriggered 
                                      ? 'Triggered at ${_formatDate(alert['triggered_at'])}'
                                      : 'Created ${_formatDate(alert['created_at'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                            trailing: isTriggered
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteAlert(alert['id']),
                                    tooltip: 'Delete alert',
                                  ),
                          ),
                        );
                      },
                    ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
