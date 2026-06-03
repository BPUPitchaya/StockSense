import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getNotifications();
      setState(() {
        _notifications = data['notifications'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load notifications: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(int notificationId) async {
    try {
      await ApiService.markNotificationRead(notificationId);
      _loadNotifications();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark as read: $e')),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await ApiService.markAllNotificationsRead();
      _loadNotifications();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark all as read: $e')),
      );
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'stock_alert':
        return Icons.trending_up;
      case 'watchlist_update':
        return Icons.star;
      case 'budget_alert':
        return Icons.account_balance_wallet;
      case 'admin_announcement':
        return Icons.announcement;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'stock_alert':
        return Colors.green;
      case 'watchlist_update':
        return Colors.blue;
      case 'budget_alert':
        return Colors.orange;
      case 'admin_announcement':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
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
                        onPressed: _loadNotifications,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No notifications', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        final notification = _notifications[index];
                        final isRead = notification['is_read'] ?? false;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isRead ? null : theme.colorScheme.primaryContainer.withOpacity(0.3),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getNotificationColor(notification['type']).withOpacity(0.2),
                              child: Icon(
                                _getNotificationIcon(notification['type']),
                                color: _getNotificationColor(notification['type']),
                              ),
                            ),
                            title: Text(
                              notification['title'] ?? 'Notification',
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(notification['message'] ?? ''),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(notification['created_at']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                            trailing: !isRead
                                ? IconButton(
                                    icon: const Icon(Icons.check),
                                    onPressed: () => _markAsRead(notification['id']),
                                    tooltip: 'Mark as read',
                                  )
                                : null,
                            onTap: () => _markAsRead(notification['id']),
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
      // Convert UTC to local time
      final localDate = date.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localDate);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hr ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${localDate.day}/${localDate.month}/${localDate.year}';
      }
    } catch (_) {
      return dateStr;
    }
  }
}
