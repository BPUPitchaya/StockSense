import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'StockSense Terms of Service',
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
              '1. Acceptance of Terms',
              'By using StockSense, you agree to these Terms of Service. If you do not agree to these terms, please do not use our service.',
            ),
            _buildSection(
              '2. Description of Service',
              'StockSense provides stock market signals, predictions, and portfolio management tools. Our predictions are based on technical analysis and historical data, and should not be considered as financial advice.',
            ),
            _buildSection(
              '3. Disclaimer',
              'StockSense is for informational purposes only. We are not financial advisors, and our predictions should not be used as the sole basis for investment decisions. Stock market investments carry risk, and you may lose money. Always conduct your own research and consult with a qualified financial advisor before making investment decisions.',
            ),
            _buildSection(
              '4. Accuracy of Information',
              'While we strive to provide accurate and timely information, we cannot guarantee the accuracy, completeness, or timeliness of any data or predictions. Stock market data is subject to change without notice.',
            ),
            _buildSection(
              '5. User Responsibilities',
              'You are responsible for maintaining the confidentiality of your account and password. You agree to notify us immediately of any unauthorized use of your account.',
            ),
            _buildSection(
              '6. Limitation of Liability',
              'StockSense shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising out of or related to your use of our service.',
            ),
            _buildSection(
              '7. Termination',
              'We reserve the right to terminate or suspend your account at any time, with or without cause, with or without notice.',
            ),
            _buildSection(
              '8. Changes to Terms',
              'We may update these terms from time to time. Continued use of the service after changes constitutes acceptance of the new terms.',
            ),
            _buildSection(
              '9. Contact Information',
              'For questions about these Terms of Service, please contact us through our support channels.',
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
