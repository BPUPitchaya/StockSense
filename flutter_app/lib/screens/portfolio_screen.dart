import 'package:flutter/material.dart';
import '../models/position.dart';
import '../services/api_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<Position> positions = [];
  double totalPortfolioValue = 0.0;
  int positionCount = 0;
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final loadedPositions = await ApiService.getPortfolio();
      final portfolioValue = await ApiService.getPortfolioValue();
      setState(() {
        positions = loadedPositions.map((p) => Position.fromJson(p)).toList();
        totalPortfolioValue = portfolioValue;
        positionCount = loadedPositions.length;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _deletePosition(int positionId) async {
    try {
      await ApiService.deletePosition(positionId);
      _loadPortfolio();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete position: $e')),
      );
    }
  }

  Future<void> _editPosition(Position position) async {
    final tickerController = TextEditingController(text: position.ticker);
    final buyPriceController = TextEditingController(text: position.buyPrice.toString());
    final quantityController = TextEditingController(text: position.quantity.toString());
    final dateController = TextEditingController(text: position.date);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tickerController,
              decoration: const InputDecoration(labelText: 'Ticker'),
              textCapitalization: TextCapitalization.characters,
            ),
            TextField(
              controller: buyPriceController,
              decoration: const InputDecoration(labelText: 'Buy Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: dateController,
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
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
              try {
                final updatedPosition = Position(
                  id: position.id,
                  ticker: tickerController.text.toUpperCase(),
                  buyPrice: double.parse(buyPriceController.text),
                  quantity: double.parse(quantityController.text),
                  date: dateController.text,
                );
                if (position.id != null) {
                  await ApiService.updatePosition(position.id!, updatedPosition);
                  Navigator.pop(context);
                  _loadPortfolio();
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update position: $e')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showAddPositionDialog() {
    final tickerController = TextEditingController();
    final buyPriceController = TextEditingController();
    final quantityController = TextEditingController();
    final dateController = TextEditingController(
      text: DateTime.now().toString().split(' ')[0],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tickerController,
              decoration: const InputDecoration(labelText: 'Ticker'),
              textCapitalization: TextCapitalization.characters,
            ),
            TextField(
              controller: buyPriceController,
              decoration: const InputDecoration(labelText: 'Buy Price'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: dateController,
              decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
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
              try {
                final position = Position(
                  ticker: tickerController.text.toUpperCase(),
                  buyPrice: double.parse(buyPriceController.text),
                  quantity: double.parse(quantityController.text),
                  date: dateController.text,
                );
                await ApiService.addPosition(position.toJson());
                Navigator.pop(context);
                _loadPortfolio();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add position: $e')),
                );
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
        title: const Text('Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPortfolio,
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
                        onPressed: _loadPortfolio,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Portfolio Value Card
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Portfolio Value',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '\$${totalPortfolioValue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$positionCount position${positionCount != 1 ? "s" : ""}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Positions List
                    Expanded(
                      child: positions.isEmpty
                          ? const Center(child: Text('No positions in portfolio'))
                          : ListView.builder(
                              itemCount: positions.length,
                              itemBuilder: (context, index) {
                                final position = positions[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: ListTile(
                                    title: Text(
                                      position.ticker,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 8),
                                        Text('Buy Price: \$${position.buyPrice.toStringAsFixed(2)}'),
                                        Text('Quantity: ${position.quantity.toStringAsFixed(4)}'),
                                        Text('Date: ${position.date}'),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => _editPosition(position),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () {
                                            if (position.id != null) {
                                              _deletePosition(position.id!);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPositionDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}