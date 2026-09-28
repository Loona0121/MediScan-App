import 'package:flutter/material.dart';
import '../widgets/web_shell.dart';
import '../utils/app_palette.dart';   // ← ADDED

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _faqs = [
    {
      'q': 'How does expiry scanning work?',
      'a': 'Point your camera at the front of the product first, then flip it to the back/expiry label. MediScan is an AI-based system that extracts the product name and expiry date automatically.'
    },
    {
      'q': 'Why is my scan result inaccurate?',
      'a': 'Blurry photos, glare, or partially covered text can affect OCR accuracy. Try rescanning in good lighting and holding the camera steady.'
    },
    {
      'q': 'Can I edit the expiry date after scanning?',
      'a': 'Yes. On the Verify Scan Results screen, you can manually correct the product name, expiry date, and category before saving. You can also edit any item later from the Inventory screen by swiping it to the left and tapping Edit.'
    },
    {
      'q': 'How do I add or remove staff accounts?',
      'a': 'Admin accounts can manage staff under Settings → Staff Management. Only admins can add or remove staff members.'
    },
    {
      'q': 'How do I generate an inventory report?',
      'a': 'From the Inventory screen, tap the report icon to open Generate Report. Choose a report type, export format (PDF or CSV), and reporting period.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3C83F6);
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    if (isWeb) {
      return WebShell(
        activeRoute: 'settings',
        activeSubRoute: 'support',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Get help or reach out to our team.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: 24),
              _buildContent(primaryBlue, p),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        surfaceTintColor: p.appBarBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Support',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [_buildContent(primaryBlue, p)],
      ),
    );
  }

  // ← CHANGED: now takes `p` so every widget can read theme-aware colors.
  Widget _buildContent(Color primaryBlue, AppPalette p) {
    final isDark = p.isDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info box — tinted blue that works in both themes.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.support_agent, color: primaryBlue, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Need help? Browse common questions below or reach out directly.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        Text(
          'FREQUENTLY ASKED QUESTIONS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: p.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),

        ..._faqs.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.cardBorder),
            ),
            child: ExpansionTile(
              // ExpansionTile inherits theme colors; give it an explicit
              // icon/text color so it reads correctly on dark cards.
              iconColor: p.textSecondary,
              collapsedIconColor: p.textSecondary,
              title: Text(
                item['q']!,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: p.textPrimary,
                ),
              ),
              childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['a']!,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'CONTACT US',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: p.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              Divider(height: 1, color: p.rowDivider),
              ListTile(
                leading: Icon(Icons.phone_outlined, color: primaryBlue),
                title: Text(
                  '+63 967 206 8175',
                  style: TextStyle(color: p.textPrimary),
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}