import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/account_service.dart';
import '../services/supabase_service.dart';
import '../widgets/web_shell.dart';
import '../widgets/top_banner.dart';
import '../utils/app_palette.dart';   // ← ADDED

class EditProfileScreen extends StatefulWidget {
  final String email;
  final String initialDisplayName;
  final String roleLabel;
  final String fullName;
  final String? initialPhotoPath;
  final String? initialUsername;

  const EditProfileScreen({
    super.key,
    required this.email,
    required this.initialDisplayName,
    required this.roleLabel,
    required this.fullName,
    this.initialPhotoPath,
    this.initialUsername,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  String? _photoPath;
  Uint8List? _photoBytes;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialDisplayName);
    _usernameCtrl = TextEditingController(text: widget.initialUsername ?? '');
    _photoPath = widget.initialPhotoPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _photoBytes = bytes;
        _isUploadingPhoto = true;
      });

      if (kIsWeb) {
        final ext = picked.name.contains('.')
            ? picked.name.split('.').last
            : 'jpg';
        final url = await SupabaseService.uploadProfilePhoto(
          email: widget.email,
          bytes: bytes,
          fileExt: ext,
        );

        if (mounted) {
          imageCache.evict(NetworkImage(url));
          setState(() {
            _photoPath = '$url?v=${DateTime.now().millisecondsSinceEpoch}';
            _isUploadingPhoto = false;
          });
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final ext = picked.path.split('.').last;
        final fileName =
            'profile_${widget.email.replaceAll('@', '_')}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final savedPath = '${dir.path}/$fileName';
        final savedFile = await File(picked.path).copy(savedPath);

        if (_photoPath != null && !_photoPath!.startsWith('http')) {
          final oldFile = File(_photoPath!);
          if (await oldFile.exists()) {
            try {
              await oldFile.delete();
            } catch (_) {}
          }
        }

        final fileBytes = await savedFile.readAsBytes();
        final url = await SupabaseService.uploadProfilePhoto(
          email: widget.email,
          bytes: fileBytes,
          fileExt: ext,
        );

        await savedFile.delete();

        if (mounted) {
          imageCache.evict(NetworkImage(url));
          setState(() {
            _photoPath = '$url?v=${DateTime.now().millisecondsSinceEpoch}';
            _isUploadingPhoto = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Pick photo error: $e');
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  ImageProvider? get _avatarImage {
    if (_photoBytes != null) return MemoryImage(_photoBytes!);
    if (_photoPath == null) return null;
    if (_photoPath!.startsWith('http')) return NetworkImage(_photoPath!);
    if (!kIsWeb) return FileImage(File(_photoPath!));
    return null;
  }

  String get _initials {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length < 2) return name.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name cannot be empty.')),
      );
      return;
    }

    if (_usernameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? photoUrlToSave;
      if (_photoPath != null && _photoPath!.startsWith('http')) {
        photoUrlToSave = _photoPath!.split('?').first;
      }

      await AccountService.saveAccount(
        email: widget.email,
        displayName: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        photoPath: photoUrlToSave,
      );

      await AccountService.refreshFromSupabase(widget.email);

      if (!mounted) return;

      TopBanner.show(context, message: 'Profile updated successfully!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ← CHANGED: takes `p` and uses theme-aware colors.
  Widget _readOnlyRow(String label, String value, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: p.textSecondary, fontSize: 14),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ← CHANGED: takes `p` so the border matches dark mode.
  Widget _avatarStack(AppPalette p, {double radius = 48}) {
    const primaryBlue = Color(0xFF3C83F6);
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: primaryBlue,
          backgroundImage: _avatarImage,
          child: _avatarImage == null
              ? Text(
                  _initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.58,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        if (_isUploadingPhoto)
          Positioned.fill(
            child: Center(
              child: SizedBox(
                width: radius * 0.7,
                height: radius * 0.7,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _isUploadingPhoto ? null : _pickPhoto,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryBlue,
                shape: BoxShape.circle,
                // ← CHANGED: ring matches the theme's card color
                border: Border.all(color: p.cardBg, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ← CHANGED: takes `p` and uses theme-aware colors.
  Widget _formCard(AppPalette p) {
    const primaryBlue = Color(0xFF3C83F6);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Display Name',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: p.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: p.searchBg,
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
                borderSide: const BorderSide(color: primaryBlue, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Username',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameCtrl,
            autocorrect: false,
            style: TextStyle(color: p.textPrimary),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.alternate_email,
                size: 18,
                color: p.textSecondary,
              ),
              filled: true,
              fillColor: p.searchBg,
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
                borderSide: const BorderSide(color: primaryBlue, width: 2),
              ),
            ),
          ),
          Divider(height: 28, color: p.rowDivider),
          Text(
            'ACCOUNT INFO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          _readOnlyRow('Full Name', widget.fullName, p),
          _readOnlyRow('Email', widget.email, p),
          _readOnlyRow('Role', widget.roleLabel, p),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    if (isWeb) return _buildWebLayout(context);
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
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
          'Edit Profile',
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: _avatarStack(p)),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _isUploadingPhoto ? null : _pickPhoto,
              child: const Text(
                'Change Photo',
                style: TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _formCard(p),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context) {
    const primaryBlue = Color(0xFF3C83F6);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = AppPalette(isDark);

    return WebShell(
      activeRoute: 'settings',
      photoUrl: _photoPath,
      displayName: _nameCtrl.text,
      headerBar: WebTopBar(
        photoUrl: _photoPath,
        initials: _initials,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: primaryBlue),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Update your display name, username, and photo',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
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
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                // ← CHANGED
                color: p.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatarStack(p, radius: 44),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed: _isUploadingPhoto ? null : _pickPhoto,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Change Photo',
                              style: TextStyle(
                                color: primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            'JPG or PNG, up to a few MB.',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _formCard(p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 