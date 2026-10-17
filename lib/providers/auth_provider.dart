import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

final supabase = Supabase.instance.client;

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  // Re-fetch whenever the session changes (sign in/out/refresh).
  ref.watch(authStateChangesProvider);

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final data = await supabase.from('profiles').select().eq('id', userId).maybeSingle();
  if (data == null) return null;
  return Profile.fromJson(data);
});

/// Profile edits. Each one writes then invalidates, so every watcher of
/// [currentProfileProvider] picks the change up.
class ProfileEditor {
  const ProfileEditor(this._ref);
  final Ref _ref;

  Future<void> _update(Map<String, dynamic> patch) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await supabase.from('profiles').update(patch).eq('id', userId);
    _ref.invalidate(currentProfileProvider);
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('Name cannot be empty.');
    if (trimmed.length > 40) throw Exception('Name is too long.');
    await _update({'display_name': trimmed});
  }

  /// Renaming goes through the RPC: it does a case-insensitive uniqueness
  /// check the unique index alone can't (@Harish and @harish read as the same
  /// handle to someone searching for a friend).
  Future<void> setUsername(String username) async {
    final trimmed = username.trim().replaceFirst(RegExp(r'^@'), '');
    try {
      await supabase.rpc('set_username', params: {'p_username': trimmed});
    } on Object catch (e) {
      final text = e.toString();
      if (text.contains('taken')) {
        throw Exception('That username is taken.');
      }
      if (text.contains('3')) {
        throw Exception(
            'Usernames are 3–20 characters: letters, numbers, dot or underscore.');
      }
      rethrow;
    }
    _ref.invalidate(currentProfileProvider);
  }

  Future<void> setBio(String bio) async {
    final trimmed = bio.trim();
    if (trimmed.length > Profile.maxBioLength) {
      throw Exception('Bio is limited to ${Profile.maxBioLength} characters.');
    }
    await _update({'bio': trimmed.isEmpty ? null : trimmed});
  }

  /// Passing null for either bound turns quiet hours off.
  Future<void> setQuietHours(TimeOfDay? start, TimeOfDay? end) =>
      _update({
        'quiet_hours_start': start == null ? null : timeOfDayToDb(start),
        'quiet_hours_end': end == null ? null : timeOfDayToDb(end),
      });

  Future<void> setDefaultReminderTime(TimeOfDay? time) =>
      _update({'default_reminder_time': timeOfDayToDb(time)});
}

final profileEditorProvider =
    Provider<ProfileEditor>((ref) => ProfileEditor(ref));
