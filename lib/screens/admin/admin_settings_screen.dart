import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/models/vibe_moderation.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/screens/admin/admin_common.dart';

/// App settings (blueprint Section 5): the maintenance notice.
/// When the switch is ON, normal (non-admin) users see the notice
/// as a banner at the top of the app.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _noticeCtrl = TextEditingController();
  bool? _on;
  bool _saving = false;
  bool _seeded = false;

  @override
  void dispose() {
    _noticeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final on = _on ?? false;
    if (on && _noticeCtrl.text.trim().isEmpty) {
      showAdminSnack(context, 'Write the notice text first.');
      return;
    }
    await runAdminAction(
      context,
      action: () => FirestoreService.instance.updateAppSettings(
        maintenanceOn: on,
        maintenanceNotice: _noticeCtrl.text,
      ),
      successMessage: 'Settings saved.',
      setBusy: (b) => setState(() => _saving = b),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('App settings')),
      body: StreamBuilder<VibeSettings>(
        stream: FirestoreService.instance.appSettings(),
        builder: (context, snap) {
          final settings = snap.data ?? const VibeSettings();
          if (!_seeded && snap.hasData) {
            _seeded = true;
            _on = settings.maintenanceOn;
            _noticeCtrl.text = settings.maintenanceNotice;
          }
          final on = _on ?? settings.maintenanceOn;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  value: on,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _on = v),
                  activeColor: AppTheme.accent,
                  title: const Text('Maintenance notice',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                    'Shown as a banner to all users while ON.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noticeCtrl,
                enabled: !_saving,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Notice text',
                  hintText:
                      'e.g. We are upgrading VibeShort tonight — uploads may be slow.',
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Save settings'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Changes apply live — no app update needed. Every change is written to the audit log.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
