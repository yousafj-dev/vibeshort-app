import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/sounds_service.dart';

/// A picked built-in sound plus its downloaded local file.
class SoundPick {
  final VibeSound sound;
  final File file;
  const SoundPick(this.sound, this.file);
}

/// Result of the sounds picker: either the user cleared the
/// selection ("No sound") or picked a track (already downloaded
/// to the device cache).
class SoundsChoice {
  final bool cleared;
  final SoundPick? pick;
  const SoundsChoice.cleared()
      : cleared = true,
        pick = null;
  const SoundsChoice.picked(this.pick) : cleared = false;
}

/// The built-in sounds picker (fix round, item 6), shared by the
/// camera screen (pick BEFORE recording — the track plays while
/// you record) and the edit screen (attach to a gallery clip).
/// All tracks are royalty-free (CC0); the file is downloaded once
/// and cached — nothing is bundled into the APK.
Future<SoundsChoice?> showSoundsSheet(
  BuildContext context, {
  String? selectedId,
}) {
  String? busyId;
  return showModalBottomSheet<SoundsChoice>(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    'Sounds',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Royalty-free tracks — free to use in your videos.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.white12,
                          child: Icon(Icons.music_off,
                              color: Colors.white70, size: 20),
                        ),
                        title: const Text('No sound',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text('Original audio only',
                            style: TextStyle(color: AppTheme.muted)),
                        onTap: busyId != null
                            ? null
                            : () => Navigator.of(sheetCtx)
                                .pop(const SoundsChoice.cleared()),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      for (final s in BuiltInSounds.all)
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.primaryGradient,
                            ),
                            child: busyId == s.id
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.music_note,
                                    color: Colors.white, size: 20),
                          ),
                          title: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: selectedId == s.id
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${s.artist} • ${s.durationLabel}',
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                          trailing: selectedId == s.id
                              ? const Icon(Icons.check_circle,
                                  color: AppTheme.accent, size: 20)
                              : null,
                          onTap: busyId != null
                              ? null
                              : () async {
                                  setSheetState(() => busyId = s.id);
                                  try {
                                    final file =
                                        await SoundCache.fileFor(s);
                                    if (!sheetCtx.mounted) return;
                                    Navigator.of(sheetCtx).pop(SoundsChoice
                                        .picked(SoundPick(s, file)));
                                  } catch (e) {
                                    if (!sheetCtx.mounted) return;
                                    setSheetState(() => busyId = null);
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(e
                                          .toString()
                                          .replaceFirst('Exception: ', '')),
                                    ));
                                  }
                                },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}
