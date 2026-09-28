import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/staff_service.dart';
import '../widgets/app_toast.dart';
import '../utils/app_palette.dart';

class AddStaffDialog extends StatefulWidget {
  const AddStaffDialog({super.key});

  @override
  State<AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<AddStaffDialog> {
  final _emailController = TextEditingController();

  static const _roles = [
    'Pharmacy Technician',
    'Pharmacist',
    'Inventory Clerk',
    'Cashier',
  ];

  String? _selectedRole;
  bool _isSaving = false;

  // Person + plus icon, no background rect.
  static const String _addStaffIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <path d="M256,136a8,8,0,0,1-8,8H232v16a8,8,0,0,1-16,0V144H200a8,8,0,0,1,0-16h16V112a8,8,0,0,1,16,0v16h16A8,8,0,0,1,256,136ZM144,157.68a68,68,0,1,0-71.9,0c-20.65,6.76-39.23,19.39-54.17,37.17A8,8,0,0,0,24,208H192a8,8,0,0,0,6.13-13.15C183.18,177.07,164.6,164.44,144,157.68Z"/>
</svg>
''';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_emailController.text.trim().isEmpty || _selectedRole == null) {
      AppToast.error(context, 'Please fill in all fields.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await StaffService.addStaff(
        email: _emailController.text.trim(),
        role: _selectedRole!,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      var message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring(11);
      }

      AppToast.error(
        context,
        'Failed to invite staff member: $message',
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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: p.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // =========================
                // HEADER
                // =========================
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: SvgPicture.string(
                        _addStaffIconSvg,
                        colorFilter: const ColorFilter.mode(
                          kPrimaryBlue,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Staff',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),

                    IconButton(
                      tooltip: 'Close',
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Divider(
                  color: p.cardBorder,
                  height: 1,
                ),

                const SizedBox(height: 24),

                // =========================
                // EMAIL
                // =========================
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email Address',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 7),

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.email,
                  ],
                  style: TextStyle(color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter staff email address',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: p.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.mail_outline,
                      size: 19,
                      color: p.textSecondary,
                    ),
                    filled: true,
                    fillColor: p.searchBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: p.cardBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: p.cardBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: kPrimaryBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // =========================
                // ROLE
                // =========================
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Role',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 7),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: p.searchBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: p.cardBorder,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      isExpanded: true,
                      hint: Text(
                        'Select department role',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: p.textMuted,
                        ),
                      ),
                      items: _roles
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(
                                role,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              setState(() {
                                _selectedRole = value;
                              });
                            },
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: kPrimaryBlue,
                      ),
                      dropdownColor: p.cardBg,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // =========================
                // INFORMATION BOX
                // =========================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: kPrimaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: kPrimaryBlue,
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

                const SizedBox(height: 26),

                // =========================
                // BUTTONS
                // =========================
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.textSecondary,
                          minimumSize: const Size(0, 48),
                          side: BorderSide(
                            color: p.cardBorder,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      flex: 2,
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
                            : const Icon(
                                Icons.mail_outline,
                                size: 19,
                              ),
                        label: Text(
                          _isSaving ? 'Sending...' : 'Send Invite',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}