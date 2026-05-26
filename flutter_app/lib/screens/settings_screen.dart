import 'package:flutter/material.dart';
import '../config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiUrlController = TextEditingController();
  List<dynamic> currencies = [];
  String? selectedCurrency;
  String? currentSymbol;
  bool isLoadingCurrencies = true;
  
  @override
  void initState() {
    super.initState();
    _apiUrlController.text = Config.apiBaseUrl;
    _loadCurrenciesAndUserCurrency();
  }

  Future<void> _loadCurrenciesAndUserCurrency() async {
    try {
      final results = await Future.wait([
        ApiService.getCurrencies(),
        ApiService.getUserCurrency(),
      ]);
      
      if (mounted) {
        setState(() {
          currencies = results[0] as List<dynamic>;
          final userCurrency = results[1] as Map<String, dynamic>;
          selectedCurrency = userCurrency['currency'];
          currentSymbol = userCurrency['symbol'];
          isLoadingCurrencies = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingCurrencies = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load currencies: $e')),
        );
      }
    }
  }

  Future<void> _updateCurrency(String currency) async {
    try {
      await ApiService.setUserCurrency(currency);
      final userCurrency = await ApiService.getUserCurrency();
      
      if (mounted) {
        setState(() {
          selectedCurrency = userCurrency['currency'];
          currentSymbol = userCurrency['symbol'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Currency changed to $currency')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update currency: $e')),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    setState(() {
      Config.setApiUrl(_apiUrlController.text);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _logout() async {
    await ApiService.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'API Configuration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Backend API URL',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                hintText: 'http://localhost:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'For laptop: http://localhost:8000',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Text(
              'For phone: http://YOUR_LAPTOP_IP:8000',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save Settings'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Currency Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            isLoadingCurrencies
                ? const Center(child: CircularProgressIndicator())
                : currencies.isEmpty
                    ? const Text('No currencies available')
                    : DropdownButtonFormField<String>(
                        value: selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'Preferred Currency',
                          border: OutlineInputBorder(),
                        ),
                        items: currencies.map((currency) {
                          return DropdownMenuItem<String>(
                            value: currency['code'],
                            child: Text('${currency['symbol']} ${currency['code']} - ${currency['name']}'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            _updateCurrency(value);
                          }
                        },
                      ),
            if (currentSymbol != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Current symbol: $currentSymbol',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }
}
