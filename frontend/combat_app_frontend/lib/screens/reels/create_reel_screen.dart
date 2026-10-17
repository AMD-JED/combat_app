import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/sport_model.dart';
import '../../providers/reels_provider.dart';
import '../../providers/sports_provider.dart';

/// New reel: pick a video, add a caption and (optionally) a sport, publish.
/// The upload goes through `/uploads/reel/video`, then `POST /reels/`.
class CreateReelScreen extends ConsumerStatefulWidget {
  const CreateReelScreen({super.key});

  @override
  ConsumerState<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends ConsumerState<CreateReelScreen> {
  static const int _maxVideoMb = 200; // backend limit on /uploads/reel/video
  static const int _maxCaption = 1000; // ReelCreate.caption

  final _picker = ImagePicker();
  final _captionController = TextEditingController();

  XFile? _file;
  int _fileSize = 0;
  int? _sportId;
  bool _sportPreselected = false;
  bool _publishing = false;
  bool _failed = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  bool get _canPublish => !_publishing && _file != null;

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 90),
    );
    if (picked == null || !mounted) return;
    final size = await picked.length();
    if (size > _maxVideoMb * 1024 * 1024) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatMediaTooLarge(_maxVideoMb))));
      return;
    }
    if (!mounted) return;
    setState(() {
      _file = picked;
      _fileSize = size;
      _failed = false;
    });
  }

  Future<void> _publish() async {
    final file = _file;
    if (!_canPublish || file == null) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _publishing = true;
      _failed = false;
    });
    try {
      await ref.read(reelsProvider.notifier).publish(
            file: file,
            caption: _captionController.text,
            sportId: _sportId,
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.reelPublished)));
      if (router.canPop()) router.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _failed = true;
      });
    }
  }

  String _sizeLabel(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sports = [
      for (final s in ref.watch(sportsListProvider).valueOrNull ?? const <SportModel>[])
        if (s.isActive) s,
    ];

    // Default the sport to the person's primary one (once, so a later manual
    // choice of "Any sport" is respected).
    if (!_sportPreselected && sports.isNotEmpty) {
      _sportPreselected = true;
      final primaryId = ref.read(sportProfilesProvider).primary?.sport.id;
      if (primaryId != null && sports.any((s) => s.id == primaryId)) {
        _sportId = primaryId;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reelCreateTitle),
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
                      l10n.reelPublish,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_publishing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              l10n.reelUploading,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
          ],
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: InkWell(
                  onTap: _publishing ? null : _pick,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _file == null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam_outlined, size: 44, color: scheme.primary),
                                  const SizedBox(height: 10),
                                  Text(
                                    l10n.reelPickVideo,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.reelPickHint,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 44, color: scheme.primary),
                                  const SizedBox(height: 10),
                                  Text(
                                    _file!.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _sizeLabel(_fileSize),
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    l10n.reelChangeVideo,
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _captionController,
            enabled: !_publishing,
            minLines: 3,
            maxLines: 5,
            maxLength: _maxCaption,
            decoration: InputDecoration(
              labelText: l10n.reelCaptionLabel,
              hintText: l10n.reelCaptionHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            // `initialValue` is read once, so the key re-creates the field
            // whenever the selection changes (preselection, user choice).
            key: ValueKey(_sportId),
            initialValue: _sportId,
            decoration: InputDecoration(labelText: l10n.sportLabel),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(l10n.reelSportNone)),
              for (final s in sports) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: _publishing ? null : (v) => setState(() => _sportId = v),
          ),
          if (_failed) ...[
            const SizedBox(height: 16),
            Text(
              l10n.reelPublishFailed,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
