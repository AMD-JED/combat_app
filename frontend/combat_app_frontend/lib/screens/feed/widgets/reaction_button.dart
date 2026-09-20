import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/post_model.dart';
import 'reaction_config.dart';

/// The post card's main "Like / reaction" button plus its floating reactions
/// picker — a port of the prototype's like button + `AthleticReactionsBar`.
///
/// Behaviour (same as the prototype):
///  * tap            -> quick reaction: "respect" if you have none, otherwise
///                      removes your current one (tap again = toggle off);
///  * long press     -> opens the picker; you can keep the finger down and
///                      slide over a reaction, releasing selects it (or
///                      lift the finger and tap one);
///  * mouse hover    -> opens the picker after ~320 ms (web / desktop) and
///                      closes it ~400 ms after the pointer leaves;
///  * tap outside    -> closes the picker.
///
/// The picker lives in an [OverlayEntry] (not inside the card): a widget
/// painted outside its parent's bounds can't receive taps in Flutter, and the
/// picker floats above the button, over the previous post.
class ReactionButton extends StatefulWidget {
  final ReactionType? current;
  final SportAccent sport;
  final void Function(ReactionType reaction) onReact;

  const ReactionButton({
    super.key,
    required this.current,
    required this.sport,
    required this.onReact,
  });

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton> {
  final LayerLink _link = LayerLink();
  final ValueNotifier<int?> _hovered = ValueNotifier<int?>(null);
  final List<GlobalKey> _itemKeys =
      List<GlobalKey>.generate(ReactionType.values.length, (_) => GlobalKey());

  OverlayEntry? _entry;
  Timer? _openTimer;
  Timer? _closeTimer;
  Timer? _bounceTimer;
  bool _bounce = false;

  bool get _isOpen => _entry != null;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _bounceTimer?.cancel();
    _closeBar();
    _hovered.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- picker

  void _openBar() {
    if (_entry != null || !mounted) return;
    _closeTimer?.cancel();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final reactions = reactionConfigsFor(l10n, widget.sport);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final overlay = Overlay.of(context);

    _hovered.value = null;
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            // Barrier: a tap anywhere else closes the picker.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeBar,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: isRtl ? Alignment.topRight : Alignment.topLeft,
              followerAnchor: isRtl ? Alignment.bottomRight : Alignment.bottomLeft,
              offset: const Offset(0, -6),
              child: Material(
                type: MaterialType.transparency,
                child: _ReactionsBar(
                  theme: theme,
                  reactions: reactions,
                  current: widget.current,
                  hovered: _hovered,
                  itemKeys: _itemKeys,
                  onSelect: _select,
                  onPointerEnter: () => _closeTimer?.cancel(),
                  onPointerExit: _scheduleClose,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _closeBar() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
    _hovered.value = null;
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 400), _closeBar);
  }

  void _select(ReactionType reaction) {
    _closeBar();
    _playBounce();
    widget.onReact(reaction);
  }

  /// While the finger is still down after a long press, finds which reaction
  /// is under it (with some vertical tolerance) so it can be magnified.
  void _updateHoverFromPointer(Offset global) {
    int? found;
    for (var i = 0; i < _itemKeys.length; i++) {
      final box = _itemKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final rect = MatrixUtils.transformRect(box.getTransformTo(null), box.paintBounds);
      final hitArea = Rect.fromLTRB(
        rect.left - 4,
        rect.top - 28,
        rect.right + 4,
        rect.bottom + 18,
      );
      if (hitArea.contains(global)) {
        found = i;
        break;
      }
    }
    if (_hovered.value != found) _hovered.value = found;
  }

  // ------------------------------------------------------------- gestures

  void _onTap() {
    if (_isOpen) {
      _closeBar();
      return;
    }
    _playBounce();
    // Sending the type you already have toggles it off on the backend.
    widget.onReact(widget.current ?? ReactionType.respect);
  }

  void _playBounce() {
    _bounceTimer?.cancel();
    if (mounted) setState(() => _bounce = true);
    _bounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _bounce = false);
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final current = widget.current;
    final config =
        current == null ? null : reactionConfigFor(current, l10n, widget.sport);
    final activeColor = config?.foreground(context);

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: activeColor ?? muted,
    );

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) {
          _closeTimer?.cancel();
          if (!_isOpen) {
            _openTimer?.cancel();
            _openTimer = Timer(const Duration(milliseconds: 320), _openBar);
          }
        },
        onExit: (_) {
          _openTimer?.cancel();
          if (_isOpen) _scheduleClose();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onLongPressStart: (_) {
            HapticFeedback.mediumImpact();
            _openBar();
          },
          onLongPressMoveUpdate: (details) => _updateHoverFromPointer(details.globalPosition),
          onLongPressEnd: (_) {
            final index = _hovered.value;
            if (index != null) {
              _select(ReactionType.values[index]);
            }
          },
          child: AnimatedScale(
            scale: _bounce ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              decoration: BoxDecoration(
                color: config?.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: config != null
                      ? config.color.withValues(alpha: 0.30)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (config != null)
                    Text(config.emoji, style: const TextStyle(fontSize: 15, height: 1))
                  else
                    Icon(Icons.thumb_up_alt_outlined, size: 18, color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      config?.label ?? l10n.likeAction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
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

/// The floating capsule with the six reactions (dock-style magnification).
class _ReactionsBar extends StatelessWidget {
  final ThemeData theme;
  final List<ReactionConfig> reactions;
  final ReactionType? current;
  final ValueNotifier<int?> hovered;
  final List<GlobalKey> itemKeys;
  final void Function(ReactionType reaction) onSelect;
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;

  const _ReactionsBar({
    required this.theme,
    required this.reactions,
    required this.current,
    required this.hovered,
    required this.itemKeys,
    required this.onSelect,
    required this.onPointerEnter,
    required this.onPointerExit,
  });

  static const double _itemSize = 38;
  static const double _labelHeight = 28;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    return MouseRegion(
      onEnter: (_) => onPointerEnter(),
      onExit: (_) => onPointerExit(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: screenWidth - 16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.bottomStart,
          child: ValueListenableBuilder<int?>(
            valueListenable: hovered,
            builder: (context, hoveredIndex, _) {
              return IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLabel(hoveredIndex),
                    const SizedBox(height: 4),
                    _buildCapsule(hoveredIndex, isDark),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Name tooltip floating above the magnified reaction.
  Widget _buildLabel(int? hoveredIndex) {
    final index = hoveredIndex;
    final x = index == null || reactions.length < 2
        ? 0.0
        : -1.0 + 2.0 * (index / (reactions.length - 1));

    return SizedBox(
      height: _labelHeight,
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment(x, 0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: index == null ? 0 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Text(
              index == null ? '' : '${reactions[index].label} ${reactions[index].emoji}',
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsule(int? hoveredIndex, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF08080C) : Colors.white).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < reactions.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _buildItem(i, hoveredIndex, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(int index, int? hoveredIndex, bool isDark) {
    final reaction = reactions[index];
    final isHovered = hoveredIndex == index;
    final isAdjacent = hoveredIndex != null && (hoveredIndex - index).abs() == 1;
    final isCurrent = current == reaction.type;

    var scale = 1.0;
    var lift = 0.0;
    var opacity = 1.0;
    if (hoveredIndex != null) {
      if (isHovered) {
        scale = 1.4;
        lift = -8;
      } else if (isAdjacent) {
        scale = 1.12;
        lift = -2;
      } else {
        scale = 0.9;
        opacity = 0.75;
      }
    }

    return MouseRegion(
      onEnter: (_) => hovered.value = index,
      onExit: (_) {
        if (hovered.value == index) hovered.value = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(reaction.type),
        child: SizedBox(
          key: itemKeys[index],
          width: _itemSize,
          height: _itemSize,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: opacity,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: Offset(0, lift / _itemSize),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isHovered
                        ? reaction.color.withValues(alpha: 0.18)
                        : isCurrent
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
                            : Colors.transparent,
                    boxShadow: isHovered
                        ? [
                            BoxShadow(
                              color: reaction.color.withValues(alpha: 0.55),
                              blurRadius: 14,
                            ),
                          ]
                        : const [],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        reaction.emoji,
                        style: const TextStyle(fontSize: 22, height: 1),
                      ),
                      if (isCurrent)
                        PositionedDirectional(
                          bottom: 1,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: reaction.color,
                            ),
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
    );
  }
}
