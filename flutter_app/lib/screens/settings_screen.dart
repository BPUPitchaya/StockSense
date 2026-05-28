import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/currency_service.dart';
import '../utils/responsive.dart';
import '../main.dart' show themeService;
import '../theme.dart' show ThemeService;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<dynamic> currencies = [];
  String? selectedCurrency;
  String? currentSymbol;
  bool isLoadingCurrencies = true;
  
  @override
  void initState() {
    super.initState();
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
      await CurrencyService.reload();
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
      body: ResponsiveBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
            const Text(
              'Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: themeService,
              builder: (context, _) {
                return SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                  ],
                  selected: {themeService.mode},
                  onSelectionChanged: (s) => themeService.setMode(s.first),
                );
              },
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
      ),
    );
  }
}
