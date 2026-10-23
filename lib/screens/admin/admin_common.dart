import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Shared building blocks for the Admin panel screens (Phase 4):
/// the reason prompt every decision goes through (blueprint
/// Section 5 — decisions are always recorded WITH a reason),
/// small display helpers and the user-name resolver.

/// Multi-line text prompt used for decision reasons, suspension
/// reasons and payout provider references. Returns the trimmed
/// text, or null when cancelled. Empty input is treated as a
/// cancel when [allowEmpty] is false.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String hint = '',
  bool allowEmpty = false,
  String confirmLabel = 'Confirm',
}) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (result == null) return null;
  if (result.isEmpty && !allowEmpty) return null;
  return result;
}

/// Simple yes/no confirmation in the admin theme.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void showAdminSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

void showAdminError(BuildContext context, Object e) {
  showAdminSnack(
      context, e.toString().replaceFirst('Exception: ', ''));
}

/// Runs an admin action with a busy flag the caller owns via
/// [setBusy]; errors surface as a snack bar.
Future<void> runAdminAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String successMessage,
  required void Function(bool busy) setBusy,
}) async {
  setBusy(true);
  try {
    await action();
    if (!context.mounted) return;
    showAdminSnack(context, successMessage);
  } catch (e) {
    if (!context.mounted) return;
    showAdminError(context, e);
  } finally {
    setBusy(false);
  }
}

/// Resolves a uid to "@username" (falling back to a short uid) —
/// admin lists reference users by id, this keeps them readable.
class UserNameText extends StatelessWidget {
  final String uid;
  final TextStyle? style;

  const UserNameText(this.uid, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const Text('—');
    return FutureBuilder(
      future: FirestoreService.instance.getUserProfile(uid),
      builder: (context, snap) {
        final p = snap.data;
        final fallback =
            uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
        final text = p == null
            ? fallback
            : (p.username.isNotEmpty ? '@${p.username}' : p.displayOrFallback);
        return Text(text, style: style);
      },
    );
  }
}

/// Small pill used for statuses across the panel.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// yyyy-MM-dd HH:mm for admin timestamps.
String fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
