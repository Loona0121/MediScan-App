import 'package:flutter/material.dart';
import '../services/staff_service.dart';
import '../utils/app_palette.dart';

/// Edit-staff dialog. Replaces the old full-screen StaffDetailScreen
/// route — opens as a modal from the pencil icon in Staff Management.
class StaffDetailDialog extends StatefulWidget {
  final StaffMember member;
  const StaffDetailDialog({super.key, required this.member});

  /// Convenience opener. Returns `true` if the staff member was updated
  /// or deleted, so the caller can refresh its list.
  static Future<bool?> show(BuildContext context, StaffMember member) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => StaffDetailDialog(member: member),
    );
  }

  @override
  State<StaffDetailDialog> createState() => _StaffDetailDialogState();
}

class _StaffDetailDialogState extends State<StaffDetailDialog> {
  late String _selectedRole;

  static const _roles = [
    'Pharmacy Technician',
    'Pharmacist',
    'Inventory Clerk',
    'Cashier',
  ];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = _roles.contains(widget.member.role)
        ? widget.member.role
        : _roles.first;
  }

  ImageProvider? get _avatarImage {
    final url = widget.member.photoUrl;
    if (url == null || url.trim().isEmpty) return null;
    return NetworkImage(url);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await StaffService.updateStaff(
        id: widget.member.id,
        fullName: widget.member.fullName,
        email: widget.member.email,
        role: _selectedRole,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove "${widget.member.fullName}" from staff?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StaffService.deleteStaff(
        widget.member.id,
        email: widget.member.email,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  Widget _readOnlyField(String label, String value, AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: p.searchBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.cardBorder),
          ),
          child: Text(
            value.isNotEmpty ? value : '—',
            style: TextStyle(fontSize: 14, color: p.textPrimary),
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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 640,
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
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Staff Details',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove staff',
                        onPressed: _isSaving ? null : _delete,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: p.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Divider(color: p.cardBorder, height: 1),

                  const SizedBox(height: 24),

                  // ── Avatar ──
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: primaryBlue,
                      backgroundImage: _avatarImage,
                      child: _avatarImage == null
                          ? Text(
                              widget.member.fullName.isNotEmpty
                                  ? widget.member.fullName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Fields ──
                  _readOnlyField('Full Name', widget.member.fullName, p),
                  const SizedBox(height: 18),
                  _readOnlyField('Email', widget.member.email, p),
                  const SizedBox(height: 18),

                  // ── Role dropdown ──
                  // Explicit fontSize + color so it matches the
                  // _readOnlyField style above (the DropdownButton was
                  // inheriting the ambient default, which read smaller
                  // than the other fields).
                  Text(
                    'Role',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: p.searchBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRole,
                        isExpanded: true,
                        isDense: false,
                        dropdownColor: p.cardBg,
                        // Match _readOnlyField's text (14pt) and use the
                        // same primary color for consistency.
                        style: TextStyle(
                          fontSize: 14,
                          color: p.textPrimary,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: p.textSecondary,
                        ),
                        items: _roles
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => _selectedRole = v);
                                }
                              },
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ── Buttons ──
                  // Cancel gets flex 2 (was 1) so "Cancel" fits on one
                  // line; Save Role keeps the wider share at flex 3.
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.textSecondary,
                            minimumSize: const Size(0, 48),
                            side: BorderSide(color: p.cardBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Role',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
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
      ),
    );
  }
}