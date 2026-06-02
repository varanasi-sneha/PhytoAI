// lib/screens/profile_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_service.dart';
import '../services/cache_service.dart';
import '../services/local_history_service.dart';
import '../services/supabase_history_service.dart';
import '../services/supabase_profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  SupabaseProfileService? _profileService;
  SupabaseHistoryService? _historyService;
  CacheService? _cacheService;
  AuthService? _authService;
  final _picker = ImagePicker();

  String? _firstName;
  String? _lastName;
  String? _email;
  String? _avatarUrl;   // https:// from Supabase Storage
  File?   _localAvatar; // offline fallback or pre-upload preview

  bool _loading = true;
  bool _uploadingPhoto = false;
  bool _isDeleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final cache = CacheService();
    await cache.init();
    _cacheService = cache;
    _authService = AuthService();
    final localHistory = LocalHistoryService(cache: cache);
    _historyService = SupabaseHistoryService(
      cache: cache,
      localHistoryService: localHistory,
    );
    _profileService = SupabaseProfileService(cache: cache);
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await _profileService!.getProfile();
      _applyRaw(raw);
    } catch (_) {
      _error = 'Failed to load profile.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccountData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will remove your profile information, scan history, and app data for your account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });

    try {
      await _historyService?.clearHistory();
      await _profileService?.deleteAccountData();
      await _cacheService?.clearAll();
      await _authService?.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account data deleted successfully.')),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Delete failed: $e'; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _isDeleting = false; });
    }
  }

  void _applyRaw(Map<String, dynamic> raw) {
    _firstName = raw['first_name'] as String?;
    _lastName  = raw['last_name']  as String?;
    _email     = raw['email']      as String?;

    final url = raw['avatar_url'] as String?;
    if (url != null && url.startsWith('http')) {
      _avatarUrl   = url;
      _localAvatar = null;
    } else if (url != null && url.isNotEmpty) {
      _localAvatar = File(url);
      _avatarUrl   = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Photo — source chooser → pick → upload
  // ---------------------------------------------------------------------------
  Future<void> _pickImage() async {
    // Show camera / gallery / remove options.
    final source = await showModalBottomSheet<_PhotoAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.camera_alt)),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.camera),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.photo_library)),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.gallery),
            ),
            if (_avatarUrl != null || _localAvatar != null)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade50,
                  child: Icon(Icons.delete_outline, color: Colors.red.shade400),
                ),
                title: Text('Remove photo',
                    style: TextStyle(color: Colors.red.shade400)),
                onTap: () => Navigator.pop(ctx, _PhotoAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    if (source == _PhotoAction.remove) {
      final removeConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Remove Photo'),
            content: const Text('Remove your current profile photo?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );
      if (removeConfirmed == true) {
        setState(() { _avatarUrl = null; _localAvatar = null; });
      }
      return;
    }

    final picked = await _picker.pickImage(
      source: source == _PhotoAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() { _localAvatar = file; _avatarUrl = null; _uploadingPhoto = true; });

    final url = await _profileService!.updateProfileImage(file);
    if (!mounted) return;
    setState(() {
      _uploadingPhoto = false;
      if (url != null) { _avatarUrl = url; _localAvatar = null; }
      // url == null → offline; keep _localAvatar preview.
    });
  }

  // ---------------------------------------------------------------------------
  // Edit bottom sheet
  // ---------------------------------------------------------------------------
  Future<void> _openEditSheet() async {
    final firstCtrl = TextEditingController(text: _firstName ?? '');
    final lastCtrl  = TextEditingController(text: _lastName  ?? '');
    final formKey   = GlobalKey<FormState>();
    bool saving     = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24, 24, 24,
                MediaQuery.of(ctx).viewInsets.bottom + 32,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Edit Profile',
                      style: Theme.of(ctx).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: firstCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: lastCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                setSheet(() => saving = true);

                                final first = firstCtrl.text.trim();
                                final last  = lastCtrl.text.trim();

                                // Capture messenger BEFORE any async gap or
                                // Navigator.pop so it's never accessed on a
                                // stale/deactivated context.
                                final messenger = ScaffoldMessenger.of(context);

                                try {
                                  await _profileService!.updateProfile(first, last);

                                  // Close sheet first, then update parent state.
                                  if (ctx.mounted) Navigator.pop(ctx);

                                  if (mounted) {
                                    setState(() {
                                      _firstName = first;
                                      _lastName  = last;
                                    });
                                  }

                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('Profile updated!')),
                                  );
                                } catch (e) {
                                  if (ctx.mounted) setSheet(() => saving = false);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Save failed: $e')),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // firstCtrl.dispose();
    // lastCtrl.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      );

  Widget _buildContent() {
    final fullName = [_firstName, _lastName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar ──────────────────────────────────────────────────────────
          _buildAvatar(),
          const SizedBox(height: 16),

          // ── Full name ───────────────────────────────────────────────────────
          Text(
            fullName.isNotEmpty ? fullName : 'Your Name',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (_email != null) ...[
            const SizedBox(height: 4),
            Text(
              _email!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
          const SizedBox(height: 36),

          // ── Info cards ──────────────────────────────────────────────────────
          _InfoCard(label: 'First Name', value: _firstName),
          const SizedBox(height: 12),
          _InfoCard(label: 'Last Name',  value: _lastName),
          const SizedBox(height: 12),
          _InfoCard(label: 'Email',      value: _email, icon: Icons.mail_outline),
          const SizedBox(height: 32),

          // ── Edit button ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openEditSheet,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              label: _isDeleting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Delete Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isDeleting ? null : _deleteAccountData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const radius = 56.0;

    ImageProvider? imageProvider;
    if (_localAvatar != null) {
      imageProvider = FileImage(_localAvatar!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_avatarUrl!);
    }

    return GestureDetector(
      onTap: _uploadingPhoto ? null : _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? const Icon(Icons.person, size: radius, color: Colors.grey)
                : null,
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: _uploadingPhoto
                ? const SizedBox(
                    height: 14, width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo source action
// ---------------------------------------------------------------------------
enum _PhotoAction { camera, gallery, remove }

// ---------------------------------------------------------------------------
// Read-only info card
// ---------------------------------------------------------------------------
class _InfoCard extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;

  const _InfoCard({
    required this.label,
    required this.value,
    this.icon = Icons.person_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  (value != null && value!.isNotEmpty) ? value! : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}