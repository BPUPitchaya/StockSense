import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'stock_alerts_screen.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  
  bool _stockAlertsEnabled = true;
  bool _watchlistUpdatesEnabled = true;
  bool _budgetAlertsEnabled = true;
  bool _adminAnnouncementsEnabled = true;
  bool _emailNotificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final preferences = await ApiService.getNotificationPreferences();
      setState(() {
        _stockAlertsEnabled = preferences['stock_alerts_enabled'] ?? true;
        _watchlistUpdatesEnabled = preferences['watchlist_updates_enabled'] ?? true;
        _budgetAlertsEnabled = preferences['budget_alerts_enabled'] ?? true;
        _adminAnnouncementsEnabled = preferences['admin_announcements_enabled'] ?? true;
        _emailNotificationsEnabled = preferences['email_notifications_enabled'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load preferences: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePreference(String key, bool value) async {
    try {
      switch (key) {
        case 'stock_alerts':
          await ApiService.updateNotificationPreferences(stockAlertsEnabled: value);
          setState(() => _stockAlertsEnabled = value);
          break;
        case 'watchlist_updates':
          await ApiService.updateNotificationPreferences(watchlistUpdatesEnabled: value);
          setState(() => _watchlistUpdatesEnabled = value);
          break;
        case 'budget_alerts':
          await ApiService.updateNotificationPreferences(budgetAlertsEnabled: value);
          setState(() => _budgetAlertsEnabled = value);
          break;
        case 'admin_announcements':
          await ApiService.updateNotificationPreferences(adminAnnouncementsEnabled: value);
          setState(() => _adminAnnouncementsEnabled = value);
          break;
        case 'email_notifications':
          await ApiService.updateNotificationPreferences(emailNotificationsEnabled: value);
          setState(() => _emailNotificationsEnabled = value);
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences updated')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
      // Revert on error
      _loadPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
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
                        onPressed: _loadPreferences,
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notification Types',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              _buildSwitchTile(
                                icon: Icons.trending_up,
                                title: 'Stock Price Alerts',
                                subtitle: 'Get notified when stocks reach target prices',
                                value: _stockAlertsEnabled,
                                onChanged: (value) => _updatePreference('stock_alerts', value),
                              ),
                              const Divider(),
                              _buildSwitchTile(
                                icon: Icons.star,
                                title: 'Watchlist Updates',
                                subtitle: 'Get notified about significant price movements in your watchlist',
                                value: _watchlistUpdatesEnabled,
                                onChanged: (value) => _updatePreference('watchlist_updates', value),
                              ),
                              const Divider(),
                              _buildSwitchTile(
                                icon: Icons.account_balance_wallet,
                                title: 'Budget Alerts',
                                subtitle: 'Get notified when spending exceeds budget',
                                value: _budgetAlertsEnabled,
                                onChanged: (value) => _updatePreference('budget_alerts', value),
                              ),
                              const Divider(),
                              _buildSwitchTile(
                                icon: Icons.announcement,
                                title: 'Admin Announcements',
                                subtitle: 'Get notified about important app updates and news',
                                value: _adminAnnouncementsEnabled,
                                onChanged: (value) => _updatePreference('admin_announcements', value),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.notifications_active),
                          title: const Text('Manage Stock Price Alerts'),
                          subtitle: const Text('Set up price alerts for your favorite stocks'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const StockAlertsScreen()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Email Notifications',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Email notifications are currently disabled. They will be enabled once a custom domain is configured for better deliverability.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSwitchTile(
                                icon: Icons.email,
                                title: 'Email Notifications',
                                subtitle: 'Receive notifications via email (requires custom domain)',
                                value: _emailNotificationsEnabled,
                                onChanged: null, // Disabled until custom domain
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

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool)? onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
