import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_session.dart';
import 'auth_provider.dart';

/// Past runs for one habit, most recent first.
final runSessionsProvider =
    FutureProvider.family<List<RunSession>, String>((ref, habitId) async {
  final rows = await supabase
      .from('run_sessions')
      .select()
      .eq('habit_id', habitId)
      .order('started_at', ascending: false)
      .limit(20);
  return rows.map((r) => RunSession.fromJson(r)).toList();
});
