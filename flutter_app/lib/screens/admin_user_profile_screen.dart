import 'package:flutter/material.dart';
import 'package:stockz_app/services/api_service.dart';

class AdminUserProfileScreen extends StatefulWidget {
  final int userId;
  final String userEmail;

  const AdminUserProfileScreen({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<AdminUserProfileScreen> createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await ApiService.getUserProfile(widget.userId);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Profile: ${widget.userEmail}'),
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
                        onPressed: _loadProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _profile == null
                  ? const Center(child: Text('User not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileCard(),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildProfileCard() {
    final profile = _profile!;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User ID
            _buildInfoRow('User ID', profile['id']?.toString() ?? 'N/A'),
            const Divider(height: 24),
            
            // First Name
            _buildInfoRow('First Name', profile['first_name'] ?? 'N/A'),
            const Divider(height: 24),
            
            // Last Name
            _buildInfoRow('Last Name', profile['last_name'] ?? 'N/A'),
            const Divider(height: 24),
            
            // Email
            _buildInfoRow('Email', profile['email'] ?? 'N/A'),
            const Divider(height: 24),
            
            // Password Hash
            _buildInfoRow(
              'Password Hash',
              profile['password_hash'] ?? 'N/A',
              isHash: true,
            ),
            const Divider(height: 24),
            
            // Preferred Currency
            _buildInfoRow('Preferred Currency', profile['preferred_currency'] ?? 'USD'),
            const Divider(height: 24),
            
            // Verification Status
            _buildInfoRow(
              'Email Verified',
              profile['is_verified'] == true ? 'Yes' : 'No',
              valueColor: profile['is_verified'] == true ? Colors.green : Colors.orange,
            ),
            const Divider(height: 24),
            
            // Created At
            _buildInfoRow('Sign Up Date', _formatDate(profile['created_at'])),
            const SizedBox(height: 24),
            
            // Password Reset Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showPasswordResetDialog,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Reset User Password'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHash = false, Color? valueColor}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (isHash)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: valueColor ?? theme.colorScheme.onSurface,
                ),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  void _showPasswordResetDialog() {
    final TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset User Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter new password for ${widget.userEmail}'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                hintText: 'Min 8 chars, 1 uppercase, 1 lowercase, 1 digit',
                border: OutlineInputBorder(),
              ),
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
              final password = passwordController.text;
              
              // Client-side validation
              if (password.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password is required')),
                  );
                }
                return;
              }
              if (password.length < 8) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 8 characters long')),
                  );
                }
                return;
              }
              if (!password.contains(RegExp(r'[A-Z]'))) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must contain at least one uppercase letter')),
                  );
                }
                return;
              }
              if (!password.contains(RegExp(r'[a-z]'))) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must contain at least one lowercase letter')),
                  );
                }
                return;
              }
              if (!password.contains(RegExp(r'[0-9]'))) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must contain at least one digit')),
                  );
                }
                return;
              }
              
              Navigator.pop(context);
              await _resetPassword(password);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String newPassword) async {
    try {
      await ApiService.resetUserPassword(widget.userId, newPassword);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset password: $e')),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
