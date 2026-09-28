import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/staff_service.dart';
import '../utils/app_palette.dart';
import '../widgets/success_dialog.dart';

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _emailController = TextEditingController();

  static const _roles = [
    'Pharmacy Technician',
    'Pharmacist',
    'Inventory Clerk',
    'Cashier',
  ];

  String? _selectedRole;
  bool _isSaving = false;

  static const primaryBlue = Color(0xFF3C83F6);

  // One shared size for both the email field and the role dropdown
  // so they read identically.
  static const double _fieldFontSize = 14;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_emailController.text.trim().isEmpty || _selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await StaffService.addStaff(
        email: _emailController.text.trim(),
        role: _selectedRole!,
      );

      if (!mounted) return;

      SuccessDialog.show(
        context,
        title: 'Invite Sent!',
        message:
            'An invitation has been sent to ${_emailController.text.trim()}.\n'
            'They will receive an email to set up their account.',
        buttonText: 'Done',
        onButtonPressed: () {
          Navigator.pop(context);      // close dialog
          Navigator.pop(context, true); // return to staff list with success
        },
      );
    } catch (e) {
      if (!mounted) return;

      var message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to invite staff member: $message'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return Scaffold(
      backgroundColor: p.scaffoldBg,

      appBar: AppBar(
        backgroundColor: p.appBarBg,
        elevation: 0,
        surfaceTintColor: p.appBarBg,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryBlue),
          onPressed: () => Navigator.pop(context),
        ),

        title: Text(
          'Add Staff',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Invite a new staff member',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Enter their email and choose a role. They will receive an invite to join.',
                style: TextStyle(
                  fontSize: 14,
                  color: p.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 28),

              // EMAIL
              Text(
                'Email Address',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                // Match the dropdown's 14pt so both fields read the same.
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: _fieldFontSize,
                ),

                decoration: InputDecoration(
                  hintText: 'Enter staff email address',
                  hintStyle: TextStyle(
                    color: p.textSecondary,
                    fontSize: _fieldFontSize,
                  ),

                  prefixIcon: Icon(
                    Icons.mail_outline,
                    color: p.textSecondary,
                  ),

                  filled: true,
                  fillColor: p.searchBg,

                  // Constrain vertical padding so the TextField's outer
                  // height matches the DropdownButton's outer height.
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.cardBorder),
                  ),

                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.cardBorder),
                  ),

                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: primaryBlue,
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ROLE
              Text(
                'Role',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              Container(
                // Match the TextField's vertical rhythm so the two
                // inputs sit at the same visual height.
                padding: const EdgeInsets.symmetric(horizontal: 14),
                constraints: const BoxConstraints(minHeight: 56),
                decoration: BoxDecoration(
                  color: p.searchBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.cardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRole,
                    isExpanded: true,
                    isDense: false,
                    dropdownColor: p.cardBg,

                    // Matches the "Role"/"Email Address" label size (13pt),
                    // and uses the same Poppins family as the web dialog.
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),

                    hint: Text(
                      'Select department role',
                      style: GoogleFonts.poppins(
                        color: p.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: primaryBlue,
                    ),

                    items: _roles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(
                          role,
                          style: GoogleFonts.poppins(
                            color: p.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      );
                    }).toList(),

                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _selectedRole = value;
                            });
                          },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // INFO BOX — tinted to work in both themes
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 19,
                      color: primaryBlue,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'The staff member will receive an email invitation to set up their name, username, and password.',
                        style: TextStyle(
                          fontSize: 12,
                          color: p.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // SEND BUTTON
              SizedBox(
                width: double.infinity,
                height: 52,

                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _register,

                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.mail_outline),

                  label: Text(
                    _isSaving ? 'Sending Invite...' : 'Send Invite',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}