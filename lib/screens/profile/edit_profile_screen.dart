import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibeshort/core/theme/app_theme.dart';
import 'package:vibeshort/services/auth_service.dart';
import 'package:vibeshort/services/firestore_service.dart';
import 'package:vibeshort/services/storage_service.dart';

/// Edit profile: photo (tap to change), display name, bio.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String _photoUrl = '';
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = AuthService.instance.uid;
    if (uid == null) return;
    final profile = await FirestoreService.instance.getUserProfile(uid);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _photoUrl = profile?.photoUrl ?? AuthService.instance.photoUrl ?? '';
      _nameCtrl.text =
          profile?.displayName ?? AuthService.instance.displayName;
      _bioCtrl.text = profile?.bio ?? '';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _changePhoto() async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      setState(() => _busy = true);
      final url =
          await StorageService.instance.uploadProfileImage(File(picked.path));
      await AuthService.instance.updatePhotoUrl(url);
      if (!mounted) return;
      setState(() => _photoUrl = url);
      _toast('Photo updated.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final uid = AuthService.instance.uid;
    if (uid == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Please enter your name.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirestoreService.instance.updateUserProfile(
        uid: uid,
        displayName: name,
        photoUrl: _photoUrl,
        bio: _bioCtrl.text.trim(),
      );
      await AuthService.instance.updateDisplayName(name);
      _toast('Profile saved.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Edit profile')),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _busy ? null : _changePhoto,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundColor: AppTheme.card,
                            backgroundImage: _photoUrl.isNotEmpty
                                ? NetworkImage(_photoUrl)
                                : null,
                            child: _photoUrl.isEmpty
                                ? const Icon(Icons.person,
                                    size: 52, color: AppTheme.muted)
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.primaryGradient,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('Tap to change photo',
                        style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'Your display name',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 3,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Tell people about yourself…',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
