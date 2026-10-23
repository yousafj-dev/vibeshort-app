import 'package:cloud_firestore/cloud_firestore.dart';

/// Safety / moderation models (Phase 4) — blueprint Sections 5, 8
/// and 9: reports, admin audit logs and the admin-editable app
/// settings. Collections: `vibeshort_reports`,
/// `vibeshort_audit_logs`, `vibeshort_blocks`,
/// `vibeshort_settings`.

/// Reasons offered when reporting a video or a user (blueprint
/// Section 9: report content/user with a reason).
class ReportReasons {
  ReportReasons._();

  static const List<String> video = [
    'Spam or misleading',
    'Violence or dangerous content',
    'Hate speech or harassment',
    'Sexual or inappropriate content',
    'Copyright violation',
    'Other',
  ];

  static const List<String> user = [
    'Impersonation',
    'Harassment or bullying',
    'Spam account',
    'Inappropriate profile',
    'Other',
  ];
}

DateTime _ts(dynamic raw) =>
    raw is Timestamp ? raw.toDate() : DateTime.now();

/// One report, `vibeshort_reports` (blueprint Section 8: id,
/// reporter_id, target_type, target_id, reason, status, resolution
/// and timestamps). Lifecycle: open → resolved | dismissed, always
/// with the decision recorded in [resolution].
class VibeReport {
  static const String statusOpen = 'open';
  static const String statusResolved = 'resolved';
  static const String statusDismissed = 'dismissed';

  final String id;
  final String reporterId;

  /// 'video' | 'user'
  final String targetType;
  final String targetId;

  /// Owner of the reported content (video uploader / the reported
  /// user), so the Admin queue and audit trail are readable.
  final String targetOwnerId;
  final String reason;
  final String status;

  /// The admin's decision reason, once resolved/dismissed.
  final String resolution;
  final String resolvedBy;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const VibeReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    this.targetOwnerId = '',
    required this.reason,
    this.status = statusOpen,
    this.resolution = '',
    this.resolvedBy = '',
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isOpen => status == statusOpen;

  String get targetLabel => targetType == 'video' ? 'Video' : 'User';

  factory VibeReport.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final res = d['resolved_at'];
    return VibeReport(
      id: doc.id,
      reporterId: (d['reporter_id'] ?? '') as String,
      targetType: (d['target_type'] ?? '') as String,
      targetId: (d['target_id'] ?? '') as String,
      targetOwnerId: (d['target_owner_id'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      status: (d['status'] ?? statusOpen) as String,
      resolution: (d['resolution'] ?? '') as String,
      resolvedBy: (d['resolved_by'] ?? '') as String,
      createdAt: _ts(d['created_at']),
      resolvedAt: res is Timestamp ? res.toDate() : null,
    );
  }
}

/// One admin action in the audit trail, `vibeshort_audit_logs`
/// (blueprint Sections 5 + 8: every moderation/payout decision is
/// preserved with who did it and why). Read-only in the panel.
class VibeAuditLog {
  final String id;
  final String adminId;

  /// 'user_suspend' | 'user_restore' | 'video_remove' |
  /// 'video_keep' | 'report_resolve' | 'report_dismiss' |
  /// 'withdrawal_approve' | 'withdrawal_reject' |
  /// 'referral_ineligible' | 'settings_update'
  final String action;

  /// 'user' | 'video' | 'report' | 'withdrawal' | 'referral' |
  /// 'settings'
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime createdAt;

  const VibeAuditLog({
    required this.id,
    required this.adminId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.reason = '',
    required this.createdAt,
  });

  String get actionLabel {
    switch (action) {
      case 'user_suspend':
        return 'User suspended';
      case 'user_restore':
        return 'User restored';
      case 'video_remove':
        return 'Video removed';
      case 'video_keep':
        return 'Video kept';
      case 'report_resolve':
        return 'Report resolved';
      case 'report_dismiss':
        return 'Report dismissed';
      case 'withdrawal_approve':
        return 'Withdrawal approved (paid)';
      case 'withdrawal_reject':
        return 'Withdrawal rejected';
      case 'referral_ineligible':
        return 'Referral marked ineligible';
      case 'settings_update':
        return 'App settings updated';
      default:
        return action;
    }
  }

  factory VibeAuditLog.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return VibeAuditLog(
      id: doc.id,
      adminId: (d['admin_id'] ?? '') as String,
      action: (d['action'] ?? '') as String,
      targetType: (d['target_type'] ?? '') as String,
      targetId: (d['target_id'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      createdAt: _ts(d['created_at']),
    );
  }
}

/// Admin-editable app settings, `vibeshort_settings/app`
/// (blueprint Section 5 "App settings": maintenance notices are
/// the one setting this phase wires end-to-end).
class VibeSettings {
  final bool maintenanceOn;
  final String maintenanceNotice;

  const VibeSettings({this.maintenanceOn = false, this.maintenanceNotice = ''});

  factory VibeSettings.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return VibeSettings(
      maintenanceOn: (d['maintenance_on'] ?? false) as bool,
      maintenanceNotice: (d['maintenance_notice'] ?? '') as String,
    );
  }
}
