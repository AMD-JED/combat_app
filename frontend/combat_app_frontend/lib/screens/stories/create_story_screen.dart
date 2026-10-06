import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/story_model.dart';
import '../../providers/stories_provider.dart';

/// New story: a photo, a video or a colored text card, with an optional
/// caption (photo/video) and a visibility choice (everyone / followers).
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  // Same limits as the backend upload endpoints (/uploads/story/*).
  static const int _maxImageMb = 10;
  static const int _maxVideoMb = 200;
  static const int _maxTextLength = 200; // StoryCreate.text_content

  static const List<Color> _palette = [
    Color(0xFF111827),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF2563EB),
  ];

  final _picker = ImagePicker();
  final _captionController = TextEditingController();
  final _textController = TextEditingController();

  StoryContentType _type = StoryContentType.image;
  StoryVisibility _visibility = StoryVisibility.public;
  Color _background = _palette[1];
  XFile? _file;
  Uint8List? _imageBytes;
  int _fileSize = 0;
  bool _publishing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _captionController.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _canPublish {
    if (_publishing) return false;
    if (_type == StoryContentType.text) return _textController.text.trim().isNotEmpty;
    return _file != null;
  }

  void _selectType(StoryContentType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // A picked photo makes no sense once the user switches to video, etc.
      _file = null;
      _imageBytes = null;
      _fileSize = 0;
      _failed = false;
    });
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final isVideo = _type == StoryContentType.video;

    final XFile? picked = isVideo
        ? await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(seconds: 60),
          )
        : await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1920,
            imageQuality: 85,
          );
    if (picked == null || !mounted) return;

    final size = await picked.length();
    final limitMb = isVideo ? _maxVideoMb : _maxImageMb;
    if (size > limitMb * 1024 * 1024) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatMediaTooLarge(limitMb))));
      return;
    }
    final bytes = isVideo ? null : await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _file = picked;
      _imageBytes = bytes;
      _fileSize = size;
      _failed = false;
    });
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() {
      _publishing = true;
      _failed = false;
    });
    try {
      final isText = _type == StoryContentType.text;
      await ref.read(storiesProvider.notifier).publish(
            contentType: _type,
            file: isText ? null : _file,
            text: isText ? _textController.text : _captionController.text,
            backgroundColor: isText ? colorToHex(_background) : null,
            visibility: _visibility,
          );
      if (!mounted) return;
      if (context.canPop()) context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storyCreateTitle),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: _publishing
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _canPublish ? _publish : null,
                    child: Text(
                      l10n.storyPublish,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<StoryContentType>(
            segments: [
              ButtonSegment(
                value: StoryContentType.image,
                icon: const Icon(Icons.image_outlined),
                label: Text(l10n.storyTypePhoto),
              ),
              ButtonSegment(
                value: StoryContentType.video,
                icon: const Icon(Icons.videocam_outlined),
                label: Text(l10n.storyTypeVideo),
              ),
              ButtonSegment(
                value: StoryContentType.text,
                icon: const Icon(Icons.text_fields),
                label: Text(l10n.storyTypeText),
              ),
            ],
            selected: {_type},
            onSelectionChanged: _publishing ? null : (s) => _selectType(s.first),
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: _type == StoryContentType.text
                    ? _TextPreview(
                        controller: _textController,
                        background: _background,
                        hint: l10n.storyTextHint,
                        maxLength: _maxTextLength,
                        enabled: !_publishing,
                      )
                    : _MediaPreview(
                        isVideo: _type == StoryContentType.video,
                        file: _file,
                        imageBytes: _imageBytes,
                        fileSize: _fileSize,
                        prompt: _type == StoryContentType.video
                            ? l10n.storyPickVideo
                            : l10n.storyPickPhoto,
                        onTap: _publishing ? null : _pick,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_type == StoryContentType.text)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: [
                for (final color in _palette)
                  GestureDetector(
                    onTap: _publishing ? null : () => setState(() => _background = color),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _background ? scheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else
            TextField(
              controller: _captionController,
              enabled: !_publishing,
              maxLength: _maxTextLength,
              decoration: InputDecoration(
                hintText: l10n.storyCaptionHint,
                border: const OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 16),
          SegmentedButton<StoryVisibility>(
            segments: [
              ButtonSegment(
                value: StoryVisibility.public,
                icon: const Icon(Icons.public),
                label: Text(l10n.storyVisibilityPublic),
              ),
              ButtonSegment(
                value: StoryVisibility.followers,
                icon: const Icon(Icons.people_outline),
                label: Text(l10n.storyVisibilityFollowers),
              ),
            ],
            selected: {_visibility},
            onSelectionChanged: _publishing ? null : (s) => setState(() => _visibility = s.first),
          ),
          if (_publishing) ...[
            const SizedBox(height: 16),
            Text(l10n.storyPublishing, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_failed) ...[
            const SizedBox(height: 16),
            Text(
              l10n.storyPublishFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final bool isVideo;
  final XFile? file;
  final Uint8List? imageBytes;
  final int fileSize;
  final String prompt;
  final VoidCallback? onTap;

  const _MediaPreview({
    required this.isVideo,
    required this.file,
    required this.imageBytes,
    required this.fileSize,
    required this.prompt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final picked = file != null;

    Widget content;
    if (!picked) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isVideo ? Icons.video_call_outlined : Icons.add_photo_alternate_outlined,
            size: 48,
            color: scheme.primary,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(prompt, textAlign: TextAlign.center),
          ),
        ],
      );
    } else if (!isVideo && imageBytes != null) {
      content = Image.memory(imageBytes!, fit: BoxFit.cover);
    } else {
      final mb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              file!.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Text('$mb MB', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SizedBox.expand(child: content),
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  final TextEditingController controller;
  final Color background;
  final String hint;
  final int maxLength;
  final bool enabled;

  const _TextPreview({
    required this.controller,
    required this.background,
    required this.hint,
    required this.maxLength,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final fg = background.computeLuminance() > 0.6 ? Colors.black : Colors.white;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [background, Color.lerp(background, Colors.black, 0.35)!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLength: maxLength,
        maxLines: null,
        textAlign: TextAlign.center,
        cursorColor: fg,
        style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          counterStyle: TextStyle(color: fg.withValues(alpha: 0.7)),
          hintText: hint,
          hintStyle: TextStyle(color: fg.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
