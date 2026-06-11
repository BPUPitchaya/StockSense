import 'package:flutter/material.dart';
import '../theme.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? DarkColors.bg : AppColors.bg;
    final surface = isDark ? DarkColors.surface : AppColors.surface;
    final border = isDark ? DarkColors.border : AppColors.border;
    final textColor = isDark ? DarkColors.text : AppColors.text;
    final mutedColor = isDark ? DarkColors.textMuted : AppColors.textMuted;
    final faintColor = isDark ? DarkColors.textFaint : AppColors.textFaint;
    final accent = isDark ? DarkColors.accent : AppColors.accent;

    return Scaffold(
      backgroundColor: bg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Navbar ──────────────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Row(
                    children: [
                      Icon(Icons.show_chart, color: accent, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'StockSense',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text('Log In', style: TextStyle(color: mutedColor, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/signup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: isDark ? DarkColors.bg : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: border),

            // ── Hero ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withOpacity(0.3)),
                    ),
                    child: Text(
                      '✦  AI-Powered Stock Analysis',
                      style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Invest Smarter,\nNot Harder.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      height: 1.1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Real-time signals, AI predictions, and portfolio tools\nbuilt for modern investors.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: mutedColor,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/signup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: isDark ? DarkColors.bg : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Start for Free', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          side: BorderSide(color: border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Free to use. No credit card required.', style: TextStyle(fontSize: 13, color: faintColor)),
                ],
              ),
            ),

            // ── Stats Bar ────────────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStat('500+', 'Stocks Tracked', textColor, mutedColor),
                  _buildStatDivider(border),
                  _buildStat('AI', 'Powered Signals', textColor, mutedColor),
                  _buildStatDivider(border),
                  _buildStat('Real-time', 'Market Data', textColor, mutedColor),
                  _buildStatDivider(border),
                  _buildStat('Free', 'To Get Started', textColor, mutedColor),
                ],
              ),
            ),

            // ── Features ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
              child: Column(
                children: [
                  Text(
                    'Everything you need to invest with confidence',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textColor, height: 1.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Powerful tools designed for both beginners and experienced investors.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: mutedColor),
                  ),
                  const SizedBox(height: 48),
                  LayoutBuilder(builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    final features = [
                      _FeatureData(Icons.bar_chart_rounded, 'Stock Signals', 'Get Buy, Sell, and Hold signals based on RSI, moving averages, and momentum indicators updated in real-time.'),
                      _FeatureData(Icons.psychology_rounded, 'AI Predictions', 'Machine learning models analyze historical patterns to forecast where a stock is headed.'),
                      _FeatureData(Icons.account_balance_wallet_rounded, 'Portfolio Tracking', 'Add your positions, track performance, and see your total portfolio value at a glance.'),
                      _FeatureData(Icons.lightbulb_rounded, 'Budget Recommendations', 'Tell us your budget and goals — AI allocates your capital across the best opportunities.'),
                      _FeatureData(Icons.notifications_rounded, 'Price Alerts', 'Set custom price targets and get notified the moment a stock hits your level.'),
                      _FeatureData(Icons.smart_toy_rounded, 'AI Stock Advisor', 'Tap any stock for a personalized Gemini AI analysis tailored to whether you own it or not.'),
                    ];
                    if (isWide) {
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: features.map((f) => SizedBox(
                          width: (constraints.maxWidth - 32) / 2,
                          child: _buildFeatureCard(f, surface, border, textColor, mutedColor, accent),
                        )).toList(),
                      );
                    }
                    return Column(
                      children: features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildFeatureCard(f, surface, border, textColor, mutedColor, accent),
                      )).toList(),
                    );
                  }),
                ],
              ),
            ),

            // ── How it works ─────────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
              child: Column(
                children: [
                  Text('How it works', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textColor)),
                  const SizedBox(height: 48),
                  _buildStep('1', 'Create an account', 'Sign up for free in under a minute.', textColor, mutedColor, accent),
                  _buildStepConnector(border),
                  _buildStep('2', 'Add your watchlist', 'Add the stocks you want to track and monitor.', textColor, mutedColor, accent),
                  _buildStepConnector(border),
                  _buildStep('3', 'Get AI insights', 'View signals, predictions, and personalised advice for every stock.', textColor, mutedColor, accent),
                  _buildStepConnector(border),
                  _buildStep('4', 'Invest with confidence', 'Use budget recommendations to allocate your capital optimally.', textColor, mutedColor, accent),
                ],
              ),
            ),

            // ── CTA Banner ───────────────────────────────────────────
            Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              decoration: BoxDecoration(
                color: accent.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withOpacity(0.25)),
              ),
              child: Column(
                children: [
                  Text(
                    'Ready to invest smarter?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: textColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Join thousands of investors using StockSense to make better decisions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: mutedColor),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/signup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: isDark ? DarkColors.bg : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Get Started — It\'s Free', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            // ── Footer ───────────────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Divider(color: border),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.show_chart, color: mutedColor, size: 18),
                      const SizedBox(width: 6),
                      Text('StockSense', style: TextStyle(color: mutedColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/terms-of-service'),
                        child: Text('Terms', style: TextStyle(color: faintColor, fontSize: 13)),
                      ),
                      Text('·', style: TextStyle(color: faintColor)),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/privacy-policy'),
                        child: Text('Privacy', style: TextStyle(color: faintColor, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('© ${DateTime.now().year} StockSense. For informational purposes only.', style: TextStyle(fontSize: 12, color: faintColor), textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, Color textColor, Color mutedColor) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textColor)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: mutedColor)),
      ],
    );
  }

  Widget _buildStatDivider(Color border) {
    return Container(width: 1, height: 40, color: border);
  }

  Widget _buildFeatureCard(_FeatureData f, Color surface, Color border, Color textColor, Color mutedColor, Color accent) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(f.icon, color: accent, size: 22),
          ),
          const SizedBox(height: 16),
          Text(f.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 8),
          Text(f.description, style: TextStyle(fontSize: 14, color: mutedColor, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String title, String desc, Color textColor, Color mutedColor, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 14, color: mutedColor, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(Color border) {
    return Padding(
      padding: const EdgeInsets.only(left: 17, top: 8, bottom: 8),
      child: Container(width: 2, height: 24, color: border),
    );
  }
}

class _FeatureData {
  final IconData icon;
  final String title;
  final String description;
  const _FeatureData(this.icon, this.title, this.description);
}
