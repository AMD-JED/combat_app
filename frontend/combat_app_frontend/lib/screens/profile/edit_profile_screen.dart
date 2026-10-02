import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/upload_service.dart';
import '../../services/user_service.dart';
import 'widgets/profile_labels.dart';

/// Edits the signed-in athlete's own profile. A Flutter port of the
/// prototype's edit form, adapted to what `PATCH /users/me` actually
/// accepts: real avatar upload (Cloudinary, already wired — no fake preset
/// gallery), the legacy single `sport_type` + `weight_class` enums (as
/// exact dropdowns, not the prototype's slightly different mock lists),
/// belt/rank, gym, location, bio, the coach toggle, and — newly exposed
/// here — [UserModel.coachName]: `coach_name` was already a real, writable
/// column and already wired into [UserService.updateProfile], it just had
/// no field in the response schemas or this form to show/edit it.
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
  late final TextEditingController _coachNameController;
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
    _coachNameController = TextEditingController(text: user.coachName ?? '');
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
    _coachNameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final url = await _uploadService.uploadAvatar(picked);
      setState(() => _avatarUrlOverride = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        coachName: _coachNameController.text.trim(),
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
        coachName: updated.coachName,
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final user = ref.watch(authProvider).user!;
    final avatarUrl = _avatarUrlOverride ?? user.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editProfileTitle),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.saveButton),
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
                    backgroundColor: theme.colorScheme.surface,
                    backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Icon(Icons.person, size: 52, color: theme.colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: accent,
                        child: _isUploadingAvatar
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
              decoration: InputDecoration(labelText: l10n.fullNameLabel),
              validator: (v) => (v == null || v.trim().length < 2) ? l10n.fullNameLengthError : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SportType>(
              initialValue: _sportType,
              decoration: InputDecoration(labelText: l10n.sportLabel),
              items: SportType.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(sportTypeLabel(l10n, s))))
                  .toList(),
              onChanged: (v) => setState(() => _sportType = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<WeightClass>(
              initialValue: _weightClass,
              decoration: InputDecoration(labelText: l10n.weightLabel),
              items: WeightClass.values
                  .map((w) => DropdownMenuItem(value: w, child: Text(weightClassLabel(l10n, w))))
                  .toList(),
              onChanged: (v) => setState(() => _weightClass = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _beltRankController,
              decoration: InputDecoration(labelText: l10n.beltRankLabel, hintText: l10n.beltRankHint),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _gymController,
              decoration: InputDecoration(labelText: l10n.gymLabel),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _coachNameController,
              decoration: InputDecoration(labelText: l10n.coachNameLabel, hintText: l10n.coachNameHint),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(labelText: l10n.locationLabel),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(labelText: l10n.bioLabel),
            ),
            SwitchListTile(
              title: Text(l10n.coachToggleLabel),
              value: _isCoach,
              activeThumbColor: accent,
              onChanged: (v) => setState(() => _isCoach = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
