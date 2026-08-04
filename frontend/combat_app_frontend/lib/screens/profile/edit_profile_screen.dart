import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/upload_service.dart';
import '../../services/user_service.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userService = UserService();
  final _uploadService = UploadService();
  final _picker = ImagePicker();

  late final TextEditingController _fullNameController;
  late final TextEditingController _beltRankController;
  late final TextEditingController _gymController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;

  SportType? _sportType;
  WeightClass? _weightClass;
  bool _isCoach = false;

  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _avatarUrlOverride;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user!;
    _fullNameController = TextEditingController(text: user.fullName);
    _beltRankController = TextEditingController(text: user.beltRank ?? '');
    _gymController = TextEditingController(text: user.gymAffiliation ?? '');
    _bioController = TextEditingController(text: user.bio ?? '');
    _locationController = TextEditingController(text: user.location ?? '');
    _sportType = user.sportType;
    _weightClass = user.weightClass;
    _isCoach = user.isCoach;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _beltRankController.dispose();
    _gymController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await _uploadService.uploadAvatar(picked.path);
      setState(() => _avatarUrlOverride = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await _userService.updateProfile(
        fullName: _fullNameController.text.trim(),
        sportType: _sportType,
        weightClass: _weightClass,
        beltRank: _beltRankController.text.trim(),
        gymAffiliation: _gymController.text.trim(),
        bio: _bioController.text.trim(),
        location: _locationController.text.trim(),
        isCoach: _isCoach,
      );
      // PATCH /users/me returns UserPublicResponse (no email/is_active/etc.)
      // Merge with the current private fields we already have locally.
      final current = ref.read(authProvider).user!;
      final merged = UserModel(
        id: updated.id,
        username: updated.username,
        fullName: updated.fullName,
        sportType: updated.sportType,
        weightClass: updated.weightClass,
        beltRank: updated.beltRank,
        gymAffiliation: updated.gymAffiliation,
        bio: updated.bio,
        avatarUrl: _avatarUrlOverride ?? updated.avatarUrl,
        location: updated.location,
        wins: updated.wins,
        losses: updated.losses,
        draws: updated.draws,
        isCoach: updated.isCoach,
        createdAt: updated.createdAt,
        email: current.email,
        isActive: current.isActive,
        isVerified: current.isVerified,
      );
      ref.read(authProvider.notifier).updateUserLocally(merged);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user!;
    final avatarUrl = _avatarUrlOverride ?? user.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: AppTheme.surface,
                    backgroundImage:
                        avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, size: 52, color: AppTheme.textMuted)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.primaryRed,
                        child: _isUploadingAvatar
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'الاسم قصير جدًا'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SportType>(
              value: _sportType,
              decoration: const InputDecoration(labelText: 'الرياضة'),
              items: SportType.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.value)))
                  .toList(),
              onChanged: (v) => setState(() => _sportType = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<WeightClass>(
              value: _weightClass,
              decoration: const InputDecoration(labelText: 'فئة الوزن'),
              items: WeightClass.values
                  .map((w) => DropdownMenuItem(value: w, child: Text(w.value)))
                  .toList(),
              onChanged: (v) => setState(() => _weightClass = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _beltRankController,
              decoration: const InputDecoration(
                labelText: 'الحزام / الرتبة',
                hintText: 'مثال: Black Belt',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _gymController,
              decoration: const InputDecoration(labelText: 'النادي / الصالة'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'الموقع'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'نبذة عني'),
            ),
            SwitchListTile(
              title: const Text('حساب مدرّب'),
              value: _isCoach,
              activeThumbColor: AppTheme.gold,
              onChanged: (v) => setState(() => _isCoach = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppTheme.primaryRed)),
            ],
          ],
        ),
      ),
    );
  }
}
