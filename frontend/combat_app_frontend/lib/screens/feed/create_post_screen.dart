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
  PostType _selectedType = PostType.text;

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
        _selectedType = PostType.image;
      });
    }
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء كتابة نص أو إرفاق صورة أولاً')),
      );
      return;
    }

    final success = await ref.read(feedProvider.notifier).createPost(
          content: content.isNotEmpty ? content : null,
          postType: _selectedType,
          imageFile: _selectedImage,
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
                children: PostType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        type == PostType.text
                            ? 'منشور'
                            : type == PostType.image
                                ? 'صورة'
                                : type == PostType.video
                                    ? 'فيديو'
                                    : 'تمرين',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textMuted,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: accent,
                      backgroundColor: AppTheme.surface,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedType = type);
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

            // Add Image Button
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library, color: AppTheme.gold),
              label: const Text('إضافة صورة', style: TextStyle(color: AppTheme.gold)),
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
