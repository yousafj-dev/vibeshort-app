import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Report flow (Phase 4, blueprint Section 9): pick a reason,
/// submit → a `vibeshort_reports` doc the Admin panel reviews.
/// Used for both videos and user profiles.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String targetOwnerId,
  required String targetLabel,
}) async {
  final reasons =
      targetType == 'video' ? ReportReasons.video : ReportReasons.user;
  var selected = reasons.first;
  var submitting = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report $targetLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Our team will review this report. Reports are private — the other user is not told who reported them.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  for (final r in reasons)
                    RadioListTile<String>(
                      value: r,
                      groupValue: selected,
                      onChanged: submitting
                          ? null
                          : (v) => setSheetState(() => selected = v ?? r),
                      title: Text(r,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14.5)),
                      activeColor: AppTheme.accent,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setSheetState(() => submitting = true);
                            try {
                              await FirestoreService.instance.submitReport(
                                targetType: targetType,
                                targetId: targetId,
                                targetOwnerId: targetOwnerId,
                                reason: selected,
                              );
                              if (!sheetCtx.mounted) return;
                              Navigator.of(sheetCtx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Report submitted. Our team will review it.'),
                                ),
                              );
                            } catch (e) {
                              if (!sheetCtx.mounted) return;
                              setSheetState(() => submitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e
                                      .toString()
                                      .replaceFirst('Exception: ', '')),
                                ),
                              );
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Submit report'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Confirmation for blocking a user, shared by the feed menu and
/// the public profile. Returns true when the block was written.
Future<bool> confirmAndBlockUser(
  BuildContext context, {
  required String targetUid,
  required String targetName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('Block $targetName?'),
      content: const Text(
          'Their videos will no longer appear in your feeds, and you will stop following them. You can undo this from their profile.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Block',
              style: TextStyle(color: Color(0xFFFF5C7A))),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await FirestoreService.instance.blockUser(targetUid);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$targetName blocked.')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    return false;
  }
}
