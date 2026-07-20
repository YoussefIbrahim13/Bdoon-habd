import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/friendship_service.dart';
import '../state/friendship_state.dart';
import '../theme/app_theme.dart';
import 'nova_components.dart';

/// Compact, state-driven add-friend control for the podium / player rows.
/// none → violet "+"; sending → spinner; pending → muted hourglass;
/// friends → emerald check. Reads its state from [FriendshipState] by id.
class AddFriendButton extends StatelessWidget {
  final String playerId;

  const AddFriendButton({super.key, required this.playerId});

  @override
  Widget build(BuildContext context) {
    final state = context.select(
        (FriendshipState f) => f.relationshipWith(playerId));

    final (icon, label, accent, enabled) = switch (state) {
      FriendState.friends => (Icons.check_rounded, 'أصحاب', AppColors.emerald, false),
      FriendState.pendingOutgoing =>
        (Icons.hourglass_top_rounded, 'قيد الانتظار', AppColors.textSecondary, false),
      FriendState.sending => (null, '...', AppColors.primaryViolet, false),
      FriendState.none => (Icons.person_add_alt_1_rounded, 'إضافة',
          AppColors.primaryViolet, true),
    };

    return Opacity(
      opacity: enabled || state == FriendState.friends ? 1 : .6,
      child: Material(
        color: accent.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled
              ? () => context.read<FriendshipState>().sendRequest(playerId)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: .55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == FriendState.sending)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 14, color: accent),
                const SizedBox(width: 6),
                Text(label,
                    style: AppText.ui(
                        size: 11.5, weight: FontWeight.w800, color: accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bell icon with a pending-count badge; opens the requests center.
class FriendRequestsBell extends StatelessWidget {
  const FriendRequestsBell({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.select((FriendshipState f) => f.pendingCount);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.people_alt_rounded,
              color: AppColors.textPrimary),
          tooltip: 'طلبات الصداقة',
          onPressed: () => showFriendRequests(context),
        ),
        if (count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.ruby,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: AppText.number(
                      size: 10, weight: FontWeight.w800, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

/// Open the Friend Requests center as a glass modal sheet.
Future<void> showFriendRequests(BuildContext context) {
  final state = context.read<FriendshipState>();
  state.refresh(); // fetch latest on open
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .55),
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: const _FriendRequestsSheet(),
    ),
  );
}

class _FriendRequestsSheet extends StatelessWidget {
  const _FriendRequestsSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FriendshipState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const DisplayHeadline('طلبات الصداقة', size: 22),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text('مفيش طلبات جديدة دلوقتي 🌙',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                          size: 14, color: AppColors.textSecondary)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.pending.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _RequestRow(request: state.pending[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final PendingRequest request;

  const _RequestRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final sender = request.sender;
    final state = context.read<FriendshipState>();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceActive,
            backgroundImage:
                sender.picture != null ? NetworkImage(sender.picture!) : null,
            child: sender.picture == null
                ? Text(sender.name.isEmpty ? '؟' : sender.name.characters.first,
                    style: AppText.ui(size: 14, weight: FontWeight.w800))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(sender.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 14.5, weight: FontWeight.w700)),
          ),
          _CircleAction(
            icon: Icons.close_rounded,
            color: AppColors.ruby,
            onTap: () => state.respond(request.requestId, accept: false),
          ),
          const SizedBox(width: 8),
          _CircleAction(
            icon: Icons.check_rounded,
            color: AppColors.emerald,
            onTap: () => state.respond(request.requestId, accept: true),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleAction(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: .6)),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}
