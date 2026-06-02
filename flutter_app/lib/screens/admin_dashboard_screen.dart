import 'package:flutter/material.dart';
import 'package:stockz_app/services/api_service.dart';
import '../config.dart';
import 'admin_user_profile_screen.dart';

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
  final TextEditingController _apiUrlController = TextEditingController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = Config.apiBaseUrl;
    _loadData();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  void _saveApiSettings() {
    setState(() {
      Config.setApiUrl(_apiUrlController.text);
      ApiService.baseUrl = Config.apiBaseUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API URL updated. Changes take effect immediately.')),
    );
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
              : IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildDashboardTab(),
                    _buildUsersTab(),
                    _buildStocksTab(),
                    _buildSystemTab(),
                  ],
                ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups),
            label: 'Users',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Stocks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'System',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    final theme = Theme.of(context);
    final recentSignups = _statistics['recent_signups'] as List? ?? [];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Row
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total',
                  '${_statistics['user_statistics']?['total_users'] ?? 0}',
                  Icons.people,
                  theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatCard(
                  'Week',
                  '${_statistics['user_statistics']?['new_users_week'] ?? 0}',
                  Icons.person_add,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatCard(
                  'Today',
                  '${_statistics['user_statistics']?['new_users_today'] ?? 0}',
                  Icons.today,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatCard(
                  'Value',
                  '\$${(_statistics['portfolio_statistics']?['total_value'] ?? 0).toStringAsFixed(0)}',
                  Icons.account_balance_wallet,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Recent Signups
          if (recentSignups.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Signups', style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => setState(() => _selectedIndex = 1),
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...recentSignups.take(3).map((user) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Text(user['id']?.toString() ?? '?', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
                ),
                title: Text(user['email'] ?? 'Unknown', overflow: TextOverflow.ellipsis),
                subtitle: Text('Joined ${_formatDate(user['created_at'])}', style: const TextStyle(fontSize: 12)),
              ),
            )),
            const SizedBox(height: 16),
          ],
          
          // Popular Stocks Preview
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Popular Stocks', style: theme.textTheme.titleMedium),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 2),
                child: const Text('See All'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPopularStocksPreview(),
        ],
      ),
    );
  }

  Widget _buildPopularStocksPreview() {
    final popularStocks = _statistics['popular_stocks'] as List? ?? [];
    if (popularStocks.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('No stocks data')),
        ),
      );
    }
    
    return Card(
      child: Column(
        children: popularStocks.take(3).map((stock) {
          final index = popularStocks.indexOf(stock);
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.trending_up, color: Colors.green.shade600, size: 20),
            ),
            title: Text(stock['ticker'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${stock['count'] ?? 0} users tracking'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('#${index + 1}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUsersTab() {
    final recentSignups = _statistics['recent_signups'] as List? ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recentSignups.isNotEmpty) ...[
            Text('Recent Signups', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...recentSignups.take(5).map((user) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  child: Text(user['id']?.toString() ?? '?', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                ),
                title: Text(_getFullName(user), overflow: TextOverflow.ellipsis),
                subtitle: Text('${user['email'] ?? 'Unknown'} • Joined ${_formatDate(user['created_at'])}', style: const TextStyle(fontSize: 12)),
                onTap: () => _navigateToUserProfile(user['id'], user['email']),
              ),
            )),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('All Users (${_users.length})', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _users.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade200,
                          child: Text(user['id'].toString(), style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(_getFullName(user), overflow: TextOverflow.ellipsis),
                        subtitle: Text(user['email'], overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteUser(user['id'], user['email']),
                        ),
                        onTap: () => _navigateToUserProfile(user['id'], user['email']),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  String _getFullName(Map<String, dynamic> user) {
    final firstName = user['first_name'] as String?;
    final lastName = user['last_name'] as String?;
    final fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return fullName.isNotEmpty ? fullName : user['email'] ?? 'Unknown';
  }

  void _navigateToUserProfile(int userId, String userEmail) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminUserProfileScreen(
          userId: userId,
          userEmail: userEmail,
        ),
      ),
    );
  }

  Widget _buildStocksTab() {
    final popularStocks = _statistics['popular_stocks'] as List? ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Popular Stocks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (popularStocks.isEmpty)
            const Center(child: Text('No stocks data'))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: popularStocks.length,
              itemBuilder: (context, index) {
                final stock = popularStocks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.trending_up, color: Colors.green.shade600),
                    ),
                    title: Text(stock['ticker'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${stock['count'] ?? 0} users tracking'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('#${index + 1}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSystemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // System Overview Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Database Status', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _buildInfoRow('Users', '${_statistics['system_info']?['user_count'] ?? 0}'),
                  _buildInfoRow('Portfolios', '${_statistics['system_info']?['portfolio_count'] ?? 0}'),
                  _buildInfoRow('Watchlists', '${_statistics['system_info']?['watchlist_count'] ?? 0}'),
                  const Divider(height: 24),
                  Text('Database URL', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    _statistics['system_info']?['database_url'] ?? 'Unknown',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // API Configuration Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.api, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('API Configuration', style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiUrlController,
                    decoration: InputDecoration(
                      labelText: 'Backend API URL',
                      hintText: 'https://your-api.com',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: _saveApiSettings,
                        tooltip: 'Save',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Local: http://localhost:8000  •  Network: http://YOUR_IP:8000',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: ${Config.apiBaseUrl}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr.substring(0, 10);
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
