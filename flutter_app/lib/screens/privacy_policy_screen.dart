import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'StockSense Privacy Policy',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Last Updated: June 2026',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '1. Information We Collect',
              'We collect information you provide directly, including your name, email address, and portfolio data. We also collect usage data and technical information such as IP address and device information.',
            ),
            _buildSection(
              '2. How We Use Your Information',
              'We use your information to provide and improve our services, personalize your experience, send notifications about stock alerts, and communicate with you about service updates.',
            ),
            _buildSection(
              '3. Data Security',
              'We implement appropriate security measures to protect your personal information. However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security.',
            ),
            _buildSection(
              '4. Third-Party Services',
              'We use third-party services for stock data (Finnhub), email delivery (SendGrid), and hosting (Render, Vercel). These services have access to your data as necessary to provide their services.',
            ),
            _buildSection(
              '5. Data Retention',
              'We retain your data for as long as necessary to provide our services. You may request deletion of your account and associated data at any time.',
            ),
            _buildSection(
              '6. Your Rights',
              'You have the right to access, correct, or delete your personal information. You can also opt out of certain communications and manage your notification preferences.',
            ),
            _buildSection(
              '7. Cookies and Tracking',
              'We use cookies and similar technologies to improve user experience and analyze usage patterns. You can manage cookie preferences through your browser settings.',
            ),
            _buildSection(
              '8. Children\'s Privacy',
              'Our service is not intended for children under 13. We do not knowingly collect personal information from children under 13.',
            ),
            _buildSection(
              '9. Changes to Privacy Policy',
              'We may update this privacy policy from time to time. We will notify users of significant changes via email or in-app notification.',
            ),
            _buildSection(
              '10. Contact Information',
              'For questions about this Privacy Policy or your personal data, please contact us through our support channels.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
