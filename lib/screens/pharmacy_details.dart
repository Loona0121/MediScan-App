import 'package:flutter/material.dart';
import '../services/pharmacy_service.dart';
import '../services/account_service.dart';
import '../services/session_service.dart';
import '../utils/app_palette.dart';   // ← ADDED

class PharmacyDetailsScreen extends StatefulWidget {
  const PharmacyDetailsScreen({super.key});

  @override
  State<PharmacyDetailsScreen> createState() => _PharmacyDetailsScreenState();
}

class _PharmacyDetailsScreenState extends State<PharmacyDetailsScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  static const _types = ['Retail Pharmacy', 'Hospital Pharmacy', 'Clinic Pharmacy'];
  String _selectedType = 'Retail Pharmacy';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _isCheckingAccess = true;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      final email = await SessionService.email;
      if (email == null || email.isEmpty) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _isCheckingAccess = false;
            _isLoading = false;
          });
        }
        return;
      }

      final isAdmin = await AccountService.isAdmin(email);
      if (!mounted) return;

      setState(() {
        _isAdmin = isAdmin;
        _isCheckingAccess = false;
      });

      if (isAdmin) {
        await _load();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('PharmacyDetails access check failed: $e');
      if (mounted) {
        setState(() {
          _isAdmin = false;
          _isCheckingAccess = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final details = await PharmacyService.getDetails();
    if (!mounted) return;
    setState(() {
      _nameController.text = details['name']!;
      _addressController.text = details['address']!;
      _phoneController.text = details['phone']!;
      _emailController.text = details['email']!;
      _selectedType =
          _types.contains(details['type']) ? details['type']! : _types.first;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    if (!_isAdmin) return;

    if (_nameController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pharmacy name and address are required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    await PharmacyService.saveDetails(
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      type: _selectedType,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pharmacy details saved!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ← CHANGED: now takes `p` so every color is theme-aware.
  Widget _field(
    String label,
    IconData icon,
    TextEditingController controller,
    AppPalette p, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.storefront_outlined, size: 16, color: Color(0xFF3C83F6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: p.searchBg,
            hintStyle: TextStyle(color: p.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: p.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF3C83F6), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3C83F6);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      // ← CHANGED
      backgroundColor: p.scaffoldBg,
      appBar: AppBar(
        // ← CHANGED
        backgroundColor: p.appBarBg,
        elevation: 0,
        surfaceTintColor: p.appBarBg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryBlue),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Pharmacy Details',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _isCheckingAccess || _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Only administrators can edit pharmacy details.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textSecondary, fontSize: 15),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        // ← CHANGED
                        color: p.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'General Information',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryBlue),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Maintain your pharmacy's public-facing records and operational details.",
                            style: TextStyle(color: p.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          _field('Pharmacy Name', Icons.storefront_outlined,
                              _nameController, p),
                          const SizedBox(height: 16),
                          _field('Business Address', Icons.location_on_outlined,
                              _addressController, p),
                          const SizedBox(height: 16),
                          _field('Contact Number', Icons.phone_outlined,
                              _phoneController, p,
                              keyboardType: TextInputType.phone),
                          const SizedBox(height: 16),
                          _field('Email Address', Icons.mail_outline,
                              _emailController, p,
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.category_outlined,
                                  size: 16, color: primaryBlue),
                              const SizedBox(width: 6),
                              Text(
                                'Pharmacy Type',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              // ← CHANGED
                              color: p.searchBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: p.cardBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedType,
                                isExpanded: true,
                                dropdownColor: p.cardBg,
                                style: TextStyle(color: p.textPrimary),
                                items: _types
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(
                                            t,
                                            style: TextStyle(color: p.textPrimary),
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _selectedType = v);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_isSaving ? 'Saving...' : 'Save Changes',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}