import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/post_provider.dart';
import '../../providers/sports_provider.dart';
import 'widgets/feed_helpers.dart';

/// New-post screen — a Flutter port of the prototype's `CreatePostModal.tsx`:
/// author row, a filled text area, media attachment (photo or video from the
/// gallery, with a preview and a remove button) and a big gradient
/// "PUBLISH" button.
///
/// Left out on purpose: the prototype's sport selector, club/location fields
/// and preset stock images — the backend's `PostCreate` only accepts
/// content, media and tags, so there is nowhere to store them.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  // Same limit as the backend's `PostCreate.content` (max_length=2000).
  static const int _maxLength = 2000;

  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  XFile? _selectedVideo;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image != null && mounted) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null;
      });
    }
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null && mounted) {
      setState(() {
        _selectedVideo = video;
        _selectedImage = null;
      });
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final content = _contentController.text.trim();

    if (content.isEmpty && _selectedImage == null && _selectedVideo == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.postEmptyError)));
      return;
    }

    // The post type is derived from the attachment by the provider
    // (video -> video, image -> image, otherwise text).
    final success = await ref.read(feedProvider.notifier).createPost(
          content: content.isNotEmpty ? content : null,
          imageFile: _selectedImage,
          videoFile: _selectedVideo,
        );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.postPublished)));
    } else {
      final error = ref.read(feedProvider).errorMessage;
      messenger.showSnackBar(SnackBar(content: Text(error ?? l10n.postFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final divider = theme.dividerColor;
    final user = ref.watch(authProvider).user;
    final sport = ref.watch(currentSportAccentProvider);
    final isPosting = ref.watch(feedProvider.select((state) => state.isPosting));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: isPosting ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.newPostTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------ author row
              Row(
                children: [
                  RoundedAvatar(url: user?.avatarUrl, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SportChip(sport: sport),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---------------------------------------------------- text
              TextField(
                controller: _contentController,
                enabled: !isPosting,
                minLines: 4,
                maxLines: 8,
                maxLength: _maxLength,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: l10n.postHint,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: muted),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: divider),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: accent),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: divider),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ------------------------------------------------- media
              Row(
                children: [
                  Icon(Icons.image_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    l10n.addMediaLabel.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MediaPickButton(
                      icon: Icons.photo_library_outlined,
                      label: l10n.addPhoto,
                      selected: _selectedImage != null,
                      onTap: isPosting ? null : _pickImage,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MediaPickButton(
                      icon: Icons.videocam_outlined,
                      label: l10n.addVideo,
                      selected: _selectedVideo != null,
                      onTap: isPosting ? null : _pickVideo,
                    ),
                  ),
                ],
              ),

              if (_selectedImage != null) ...[
                const SizedBox(height: 12),
                _AttachmentFrame(
                  onRemove: isPosting ? null : () => setState(() => _selectedImage = null),
                  child: FutureBuilder(
                    future: _selectedImage!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        );
                      }
                      return SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator(color: accent)),
                      );
                    },
                  ),
                ),
              ],

              // No inline player yet (the backend has nowhere to store the
              // auto-generated thumbnail), so the preview just confirms
              // what is attached.
              if (_selectedVideo != null) ...[
                const SizedBox(height: 12),
                _AttachmentFrame(
                  onRemove: isPosting ? null : () => setState(() => _selectedVideo = null),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    color: theme.colorScheme.surface,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam, color: accent, size: 32),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _selectedVideo!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (isPosting && _selectedVideo != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.postUploadingVideoNote,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),

              // ------------------------------------------------ publish
              Opacity(
                opacity: isPosting ? 0.7 : 1,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: accentGradient(accent),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: isPosting ? null : _submit,
                      child: Center(
                        child: isPosting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const DirectionalSendIcon(size: 18, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.publishButton,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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

class _MediaPickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _MediaPickButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = selected ? accent : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.6) : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded preview frame with a remove (X) button in the top corner.
class _AttachmentFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onRemove;

  const _AttachmentFrame({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          child,
          PositionedDirectional(
            top: 8,
            end: 8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.75),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
