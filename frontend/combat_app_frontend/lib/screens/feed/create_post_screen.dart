import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../models/post_model.dart';
import '../../providers/post_provider.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  XFile? _selectedVideo;
  PostType _selectedType = PostType.text;

  // "workout" exists on PostType for forward-compatibility with V8
  // (Training & AI Coach), but the backend's own PostType enum only
  // accepts text/image/video today (see app/models/post.py) — offering it
  // here would let someone pick a type the API will reject. Only show
  // what's actually wired end-to-end.
  static const _availableTypes = [PostType.text, PostType.image, PostType.video];

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null;
        _selectedType = PostType.image;
      });
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);

    if (video != null) {
      setState(() {
        _selectedVideo = video;
        _selectedImage = null;
        _selectedType = PostType.video;
      });
    }
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImage == null && _selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء كتابة نص أو إرفاق صورة/فيديو أولاً')),
      );
      return;
    }

    final success = await ref.read(feedProvider.notifier).createPost(
          content: content.isNotEmpty ? content : null,
          postType: _selectedType,
          imageFile: _selectedImage,
          videoFile: _selectedVideo,
        );

    if (mounted && success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر المنشور بنجاح!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('منشور جديد'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: feedState.isPosting ? null : _submitPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                minimumSize: const Size(80, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: feedState.isPosting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('نشر', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post type selector pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _availableTypes.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        type == PostType.text
                            ? 'منشور'
                            : type == PostType.image
                                ? 'صورة'
                                : 'فيديو',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textMuted,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: accent,
                      backgroundColor: AppTheme.surface,
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() {
                          _selectedType = type;
                          // Switching type away from what's attached clears
                          // the mismatched attachment instead of silently
                          // keeping e.g. a picked video while "صورة" shows.
                          if (type != PostType.image) _selectedImage = null;
                          if (type != PostType.video) _selectedVideo = null;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Content input field
            TextField(
              controller: _contentController,
              maxLines: 6,
              style: const TextStyle(color: AppTheme.onSurface, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'ما الذي يدور في ذهنك اليوم يا بطل؟...',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                border: InputBorder.none,
                filled: false,
              ),
            ),

            const SizedBox(height: 16),

            // Image Preview if picked
            if (_selectedImage != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                        return Container(
                          height: 200,
                          color: AppTheme.surface,
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _selectedImage = null;
                            _selectedType = PostType.text;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Video preview if picked — no inline player yet (the backend
            // has nowhere to store the auto-generated thumbnail today), so
            // this just confirms what's attached rather than pretending to
            // play it back.
            if (_selectedVideo != null) ...[
              Stack(
                children: [
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam, color: accent, size: 32),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _selectedVideo!.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _selectedVideo = null;
                            _selectedType = PostType.text;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Add Image/Video button — action matches whichever pill is
            // selected; hidden for a plain text post.
            if (_selectedType == PostType.image)
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library, color: AppTheme.gold),
                label: const Text('إضافة صورة', style: TextStyle(color: AppTheme.gold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.gold),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )
            else if (_selectedType == PostType.video)
              OutlinedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.videocam, color: AppTheme.gold),
                label: const Text('إضافة فيديو', style: TextStyle(color: AppTheme.gold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.gold),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
