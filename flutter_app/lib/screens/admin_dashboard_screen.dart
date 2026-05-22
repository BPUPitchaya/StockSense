import 'package:flutter/material.dart';
import 'package:stockz_app/services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _statistics = {};
  List<dynamic> _users = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stats = await ApiService.getAdminStatistics();
      final users = await ApiService.getAllUsers();
      setState(() {
        _statistics = stats;
        _users = users['users'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteUser(int userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteUser(userId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete user: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
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
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Statistics Cards
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Total Users',
                                '${_statistics['user_statistics']?['total_users'] ?? 0}',
                                Icons.people,
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                'New This Week',
                                '${_statistics['user_statistics']?['new_users_week'] ?? 0}',
                                Icons.person_add,
                                Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'New Today',
                                '${_statistics['user_statistics']?['new_users_today'] ?? 0}',
                                Icons.today,
                                Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildStatCard(
                                'Portfolio Value',
                                '\$${(_statistics['portfolio_statistics']?['total_value'] ?? 0).toStringAsFixed(2)}',
                                Icons.account_balance_wallet,
                                Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Popular Stocks
                      _buildSection(
                        'Popular Stocks',
                        (_statistics['popular_stocks'] as List?)?.isEmpty ?? true
                            ? const Center(child: Text('No stocks data'))
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: (_statistics['popular_stocks'] as List).length,
                                itemBuilder: (context, index) {
                                  final stock = _statistics['popular_stocks'][index];
                                  return ListTile(
                                    leading: const Icon(Icons.trending_up),
                                    title: Text(stock['ticker'] ?? 'Unknown'),
                                    trailing: Text('${stock['count'] ?? 0} users'),
                                  );
                                },
                              ),
                      ),
                      
                      // Recent Signups
                      _buildSection(
                        'Recent Signups',
                        (_statistics['recent_signups'] as List?)?.isEmpty ?? true
                            ? const Center(child: Text('No recent signups'))
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: (_statistics['recent_signups'] as List).length,
                                itemBuilder: (context, index) {
                                  final user = _statistics['recent_signups'][index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text(user['id']?.toString() ?? '?'),
                                    ),
                                    title: Text(user['email'] ?? 'Unknown'),
                                    subtitle: Text('Created: ${user['created_at']?.substring(0, 10) ?? 'N/A'}'),
                                  );
                                },
                              ),
                      ),
                      
                      // System Info
                      _buildSection(
                        'System Info',
                        Column(
                          children: [
                            _buildInfoRow('Database', _statistics['system_info']?['database_url'] ?? 'Unknown'),
                            _buildInfoRow('Users', '${_statistics['system_info']?['user_count'] ?? 0}'),
                            _buildInfoRow('Portfolios', '${_statistics['system_info']?['portfolio_count'] ?? 0}'),
                            _buildInfoRow('Watchlists', '${_statistics['system_info']?['watchlist_count'] ?? 0}'),
                          ],
                        ),
                      ),
                      
                      // All Users Section
                      _buildSection(
                        'All Users',
                        _users.isEmpty
                            ? const Center(child: Text('No users found'))
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _users.length,
                                itemBuilder: (context, index) {
                                  final user = _users[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        child: Text(user['id'].toString()),
                                      ),
                                      title: Text(user['email']),
                                      subtitle: Text(
                                        'Created: ${user['created_at']?.substring(0, 10) ?? 'N/A'}',
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _deleteUser(user['id'], user['email']),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        content,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
