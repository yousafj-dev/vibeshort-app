import 'package:flutter/material.dart';
import 'package:vibeshort/services/auth_service.dart';

/// DIAGNOSTIC BUILD ONLY: renders [AuthService.diagLines] — the
/// timestamped auth-restore log — in a small monospace panel
/// that stays pinned to the newest line. Shown on the splash
/// until routing completes, and mirrored at the bottom of the
/// login screen so the full ~12 s sequence (including the 10 s
/// snapshot) can still be screenshotted after the gate has
/// routed. Purely observational: it reads the log, it never
/// influences routing.
class AuthDiagLog extends StatefulWidget {
  const AuthDiagLog({super.key, this.height = 170});

  final double height;

  @override
  State<AuthDiagLog> createState() => _AuthDiagLogState();
}

class _AuthDiagLogState extends State<AuthDiagLog> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final lines = AuthService.instance.diagLines;
        _stickToBottom();
        return Container(
          width: 332,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AUTH RESTORE LOG — diagnostic build',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: lines.length,
                  itemBuilder: (_, i) => Text(
                    lines[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.4,
                      color: Color(0xFF9BE89B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
