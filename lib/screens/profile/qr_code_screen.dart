import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';

/// Your QR code (settings pack): encodes `vibeshort://user/{uid}`
/// so another VibeShort user can reach this profile from the
/// code. Display only — no scanner ships in this version.
class QrCodeScreen extends StatelessWidget {
  const QrCodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(
            child: Text('Please log in.',
                style: TextStyle(color: AppTheme.muted))),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Your QR code')),
      body: StreamBuilder(
        stream: FirestoreService.instance.userProfile(uid),
        builder: (context, snap) {
          final profile = snap.data;
          final name = profile?.displayOrFallback ??
              AuthService.instance.displayName;
          final username = profile?.username ?? '';
          final photo = profile?.photoUrl ?? '';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(
                      data: 'vibeshort://user/$uid',
                      version: QrVersions.auto,
                      size: 230,
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 26),
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.card,
                    backgroundImage:
                        photo.isNotEmpty ? NetworkImage(photo) : null,
                    child: photo.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800),
                  ),
                  if (username.isNotEmpty)
                    Text('@$username',
                        style: const TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 14),
                  const Text(
                    'Anyone with VibeShort can open your profile from this code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
