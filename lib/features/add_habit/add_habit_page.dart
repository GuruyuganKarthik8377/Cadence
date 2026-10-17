import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../models/habit.dart';
import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/habit_link_provider.dart';
import '../../providers/habit_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Shared mutable state: user-created categories and units persist in-session.
// In production these would come from local storage / Firestore.
// ---------------------------------------------------------------------------

final List<String> userCategories = ['Health', 'Learning', 'Fitness', 'Mindfulness', 'Productivity'];
final List<String> userDurationUnits = ['minutes', 'times', 'pages'];

// ---------------------------------------------------------------------------
// Preset icon options
// ---------------------------------------------------------------------------

const _iconOptions = [
  'bookOpen', 'wind', 'dumbbell', 'footprints', 'code', 'apple', 'music',
  'palette', 'penLine', 'leaf', 'activity', 'flame', 'brain', 'sun', 'droplet',
  'camera', 'briefcase', 'graduationCap', 'zap', 'star', 'bed', 'shoppingBag',
  'clock', 'trophy', 'smile', 'target', 'heart', 'bike', 'coffee', 'moon'
];

// ---------------------------------------------------------------------------
// Starter templates — one tap fills the whole form. Shown only while creating
// a brand-new habit and nothing has been typed yet.
// ---------------------------------------------------------------------------

typedef HabitTemplate = ({
  String name,
  String icon,
  String category,
  int value,
  String unit,
});

const List<HabitTemplate> habitTemplates = [
  (name: 'Morning Run', icon: 'footprints', category: 'Fitness', value: 30, unit: 'minutes'),
  (name: 'Gym', icon: 'dumbbell', category: 'Fitness', value: 45, unit: 'minutes'),
  (name: 'Read', icon: 'bookOpen', category: 'Learning', value: 20, unit: 'pages'),
  (name: 'Meditate', icon: 'wind', category: 'Mindfulness', value: 10, unit: 'minutes'),
  (name: 'Drink Water', icon: 'droplet', category: 'Health', value: 8, unit: 'times'),
  (name: 'Sleep by 11', icon: 'moon', category: 'Health', value: 0, unit: 'minutes'),
  (name: 'Journal', icon: 'penLine', category: 'Mindfulness', value: 10, unit: 'minutes'),
  (name: 'Study', icon: 'graduationCap', category: 'Learning', value: 60, unit: 'minutes'),
];

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class AddHabitPage extends ConsumerStatefulWidget {
  final Habit? habit;
  const AddHabitPage({super.key, this.habit});

  @override
  ConsumerState<AddHabitPage> createState() => _AddHabitPageState();
}

class _AddHabitPageState extends ConsumerState<AddHabitPage> {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _customCategoryController = TextEditingController();
  final _customTypeController = TextEditingController();
  final _durationController = TextEditingController(text: '0');
  final _customUnitController = TextEditingController();
  final _scrollController = ScrollController();

  String _iconKey = 'bookOpen';
  String _selectedCategory = '';
  HabitType _habitType = HabitType.build;
  FrequencyType _frequency = FrequencyType.daily;
  final Set<int> _selectedDays = {};
  /// Weekdays taken off on purpose — skipped rather than counted as misses.
  final Set<int> _restDays = {};
  int _timesPerWeek = 3;
  String _durationUnit = 'minutes';
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);
  bool _repeatReminder = false;
  // "Keep reminding until done" — distinct from _repeatReminder, which is
  // about which *days* get a reminder at all.
  bool _repeatUntilDone = false;
  int _repeatIntervalMinutes = 30;
  int _repeatMaxCount = 3;
  String? _coverImageUrl;
  bool _linkToFriend = false;
  String? _linkedFriendId;
  String? _linkedFriendName;
  String? _linkedFriendHabitId;
  String? _linkedFriendHabitName;

  bool _locationEnabled = false;
  String? _locationName;
  double? _locationLat;
  double? _locationLng;
  final _locationSearchController = TextEditingController();
  List<PlaceResult> _locationResults = [];
  bool _locationSearching = false;
  Timer? _locationDebounce;

  bool _uploadingCover = false;

  // ── Validation ─────────────────────────────────────────────────────────────
  bool _showErrors = false;
  bool _isSubmitting = false;

  /// True when the cover URL points at our own storage bucket (an upload),
  /// as opposed to one of the bundled preset images.
  bool _isUploadedCover(String url) => !presetCoverImages.contains(url);

  Future<void> _pickCoverImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 82,
      );
      if (picked == null) return;

      setState(() => _uploadingCover = true);
      final bytes = await picked.readAsBytes();
      final userId = supabase.auth.currentUser!.id;
      final path =
          'covers/$userId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('user-content').uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = supabase.storage.from('user-content').getPublicUrl(path);
      if (mounted) setState(() => _coverImageUrl = url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't upload image. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _selectedCategory.isNotEmpty &&
      (_habitType != HabitType.custom ||
          _customTypeController.text.trim().isNotEmpty);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.habit != null) {
      final h = widget.habit!;
      _nameController.text = h.name;
      _iconKey = h.iconOrEmoji;
      _selectedCategory = h.category;
      if (!userCategories.contains(h.category)) {
        userCategories.add(h.category);
      }
      _habitType = h.habitType;
      if (h.habitType == HabitType.custom) {
        _customTypeController.text = h.customTypeLabel ?? '';
      }
      _frequency = h.frequency;
      _restDays.addAll(h.restDays);
      if (h.frequency == FrequencyType.specificDays) {
        _selectedDays.addAll(h.specificDays);
      } else if (h.frequency == FrequencyType.timesPerWeek) {
        _timesPerWeek = h.timesPerWeek;
      }
      _durationController.text = h.durationValue.toString();
      _durationUnit = h.durationUnit;
      if (!userDurationUnits.contains(h.durationUnit)) {
        userDurationUnits.add(h.durationUnit);
      }
      _reminderEnabled = h.reminderEnabled;
      if (h.reminderTime != null) {
        _reminderTime = h.reminderTime!;
      }
      _repeatReminder = h.repeatReminderDaily;
      _repeatUntilDone = h.repeatUntilDone;
      _repeatIntervalMinutes = h.repeatIntervalMinutes;
      _repeatMaxCount = h.repeatMaxCount;
      _coverImageUrl = h.coverImageUrl;
      if (h.hasLocation) {
        _locationEnabled = true;
        _locationName = h.locationName;
        _locationLat = h.locationLat;
        _locationLng = h.locationLng;
      }
    } else {
      // New habit: pre-fill the reminder from the account default, if set.
      // Read (not watched) — this is a one-time seed, and later edits to the
      // default shouldn't rewrite a form the user is already filling in.
      final fallback =
          ref.read(currentProfileProvider).valueOrNull?.defaultReminderTime;
      if (fallback != null) {
        _reminderTime = fallback;
        _reminderEnabled = true;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customCategoryController.dispose();
    _customTypeController.dispose();
    _durationController.dispose();
    _customUnitController.dispose();
    _scrollController.dispose();
    _locationSearchController.dispose();
    _locationDebounce?.cancel();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(
            primary: context.colors.primaryAccent,
            onPrimary: context.colors.onAccent,
            surface: context.colors.primarySurface,
          ),
          dialogTheme: const DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _reminderTime = picked);
  }

  void _addCustomCategory() async {
    final result = await _showInputSheet(
      context: context,
      title: 'Custom Category',
      hint: 'e.g. Cooking, Music Practice',
      controller: _customCategoryController,
    );
    if (result != null && result.trim().isNotEmpty) {
      final cat = result.trim();
      setState(() {
        if (!userCategories.contains(cat)) userCategories.add(cat);
        _selectedCategory = cat;
        _customCategoryController.clear();
      });
    }
  }

  void _addCustomUnit() async {
    final result = await _showInputSheet(
      context: context,
      title: 'Custom Unit',
      hint: 'e.g. glasses of water, km',
      controller: _customUnitController,
    );
    if (result != null && result.trim().isNotEmpty) {
      final unit = result.trim();
      setState(() {
        if (!userDurationUnits.contains(unit)) userDurationUnits.add(unit);
        _durationUnit = unit;
        _customUnitController.clear();
      });
    }
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _IconPickerSheet(
        current: _iconKey,
        onPick: (val) => setState(() => _iconKey = val),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_isValid) {
      setState(() => _showErrors = true);
      return;
    }

    setState(() => _isSubmitting = true);

    final habit = Habit(
      id: widget.habit?.id ?? '',
      name: _nameController.text.trim(),
      iconOrEmoji: _iconKey,
      category: _selectedCategory,
      habitType: _habitType,
      customTypeLabel: _habitType == HabitType.custom ? _customTypeController.text.trim() : null,
      frequency: _frequency,
      specificDays: _frequency == FrequencyType.specificDays ? _selectedDays.toList() : const [],
      timesPerWeek: _frequency == FrequencyType.timesPerWeek ? _timesPerWeek : 1,
      durationValue: int.tryParse(_durationController.text) ?? 0,
      durationUnit: _durationUnit,
      reminderEnabled: _reminderEnabled,
      reminderTime: _reminderEnabled ? _reminderTime : null,
      repeatReminderDaily: _repeatReminder,
      repeatUntilDone: _repeatUntilDone,
      repeatIntervalMinutes: _repeatIntervalMinutes,
      repeatMaxCount: _repeatMaxCount,
      coverImageUrl: _coverImageUrl,
      locationName: _locationEnabled ? _locationName : null,
      locationLat: _locationEnabled ? _locationLat : null,
      locationLng: _locationEnabled ? _locationLng : null,
      sortOrder: widget.habit?.sortOrder ?? 0,
      restDays: _restDays.toList()..sort(),
    );

    try {
      if (widget.habit != null) {
        await ref.read(habitsProvider.notifier).updateHabit(habit);
      } else {
        final newHabitId = await ref.read(habitsProvider.notifier).addHabit(habit);
        if (_linkToFriend && _linkedFriendId != null && _linkedFriendHabitId != null) {
          final friends = ref.read(friendsProvider).valueOrNull?.friends ?? const <Friend>[];
          final friend = friends.where((f) => f.id == _linkedFriendId).firstOrNull;
          if (friend != null) {
            await ref.read(habitLinksProvider.notifier).createLink(
                  userHabitId: newHabitId,
                  friendHabitId: _linkedFriendHabitId!,
                  friendshipId: friend.friendshipId,
                );
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.habit != null
                ? '"${_nameController.text.trim()}" updated successfully.'
                : '"${_nameController.text.trim()}" added successfully.',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
          backgroundColor: context.colors.primaryAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Something went wrong. Please try again.',
            style: TextStyle(fontFamily: 'Inter'),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: context.colors.background,
      // Keyboard safe-area handled by resizeToAvoidBottomInset (default true)
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: context.colors.primaryAccent, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.habit != null ? 'Edit Habit' : 'New Habit',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _buildTemplatesSection(),
                  _buildNameSection(),
                  _buildDivider(),
                  _buildCategorySection(),
                  _buildDivider(),
                  _buildHabitTypeSection(),
                  _buildDivider(),
                  _buildFrequencySection(),
                  _buildDivider(),
                  _buildDurationSection(),
                  _buildDivider(),
                  _buildReminderSection(),
                  _buildDivider(),
                  _buildCoverImageSection(),
                  _buildDivider(),
                  _buildLocationSection(),
                  _buildDivider(),
                  _buildAccountabilitySection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          // ── Fixed bottom CTA ────────────────────────────────────────────
          _buildSaveButton(bottomPadding),
        ],
      ),
    );
  }

  // ── Section: Starter templates ──────────────────────────────────────────

  void _applyTemplate(HabitTemplate t) {
    setState(() {
      _nameController.text = t.name;
      _iconKey = t.icon;
      _selectedCategory = t.category;
      if (!userCategories.contains(t.category)) userCategories.add(t.category);
      _durationController.text = t.value.toString();
      _durationUnit = t.unit;
      if (!userDurationUnits.contains(t.unit)) userDurationUnits.add(t.unit);
    });
  }

  Widget _buildTemplatesSection() {
    // Editing an existing habit, or the user has already started typing —
    // templates would only get in the way.
    if (widget.habit != null || _nameController.text.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start from a template',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: habitTemplates
                .map((t) => GestureDetector(
                      onTap: () => _applyTemplate(t),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.colors.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(habitIconData(t.icon),
                                size: 14, color: context.colors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              t.name,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Section: Habit Name + Emoji ─────────────────────────────────────────

  Widget _buildNameSection() {
    final nameError = _showErrors && _nameController.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon circle
            GestureDetector(
              onTap: _showIconPicker,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.colors.border),
                ),
                child: Center(
                  child: Icon(
                    habitIconData(_iconKey),
                    size: 26,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name field
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.primarySurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: nameError ? Colors.red : context.colors.border,
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'What habit do you want to build?',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: context.colors.textSecondary,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (nameError)
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Please enter a habit name.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Section: Category ───────────────────────────────────────────────────

  Widget _buildCategorySection() {
    final catError = _showErrors && _selectedCategory.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Category'),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              ...userCategories.map((cat) => _CategoryPill(
                    label: cat,
                    isSelected: _selectedCategory == cat,
                    onTap: () => setState(() => _selectedCategory = cat),
                  )),
              // + Custom
              _CategoryPill(
                label: '+ Custom',
                isSelected: false,
                isDashed: true,
                onTap: _addCustomCategory,
              ),
            ],
          ),
        ),
        if (catError)
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 2),
            child: Text(
              'Please select a category.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.red),
            ),
          ),
      ],
    );
  }

  // ── Section: Habit Type ─────────────────────────────────────────────────

  Widget _buildHabitTypeSection() {
    final customTypeError = _showErrors &&
        _habitType == HabitType.custom &&
        _customTypeController.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Habit Type'),
        const SizedBox(height: 12),
        _HabitTypeCard(
          icon: LucideIcons.trendingUp,
          title: 'Build',
          description: 'A positive habit to practise regularly',
          isSelected: _habitType == HabitType.build,
          onTap: () => setState(() => _habitType = HabitType.build),
        ),
        const SizedBox(height: 10),
        _HabitTypeCard(
          icon: LucideIcons.trendingDown,
          title: 'Break',
          description: 'A habit to reduce or quit over time',
          isSelected: _habitType == HabitType.breakHabit,
          onTap: () => setState(() => _habitType = HabitType.breakHabit),
        ),
        const SizedBox(height: 10),
        _HabitTypeCard(
          icon: LucideIcons.sparkles,
          title: 'Custom',
          description: 'Define your own habit category',
          isSelected: _habitType == HabitType.custom,
          onTap: () => setState(() => _habitType = HabitType.custom),
        ),
        if (_habitType == HabitType.custom) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: context.colors.primarySurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: customTypeError ? Colors.red : context.colors.border,
              ),
            ),
            child: TextField(
              controller: _customTypeController,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Name your habit type',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: context.colors.textSecondary,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (customTypeError)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Please name your custom type.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.red),
              ),
            ),
        ],
      ],
    );
  }

  // ── Section: Frequency ──────────────────────────────────────────────────

  Widget _buildFrequencySection() {
    const labels = ['Daily', 'Specific Days', 'X per week'];
    const types = [FrequencyType.daily, FrequencyType.specificDays, FrequencyType.timesPerWeek];
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'How often?'),
        const SizedBox(height: 12),
        // Segmented pills
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.secondarySurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: List.generate(3, (i) {
              final sel = _frequency == types[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _frequency = types[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: sel ? context.colors.primaryAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // Specific days
        if (_frequency == FrequencyType.specificDays) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final sel = _selectedDays.contains(i);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (sel) {
                      _selectedDays.remove(i);
                    } else {
                      _selectedDays.add(i);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: sel ? context.colors.primaryAccent : context.colors.primarySurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? context.colors.primaryAccent : context.colors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    days[i],
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : context.colors.textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
        // Rest days — off-days that don't count as misses.
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(LucideIcons.coffee, size: 15, color: context.colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Rest days',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "won't break your streak",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final sel = _restDays.contains(i);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) {
                  _restDays.remove(i);
                } else {
                  _restDays.add(i);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: sel
                      ? context.colors.secondarySurface
                      : context.colors.primarySurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sel
                        ? context.colors.textSecondary
                        : context.colors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  days[i],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel
                        ? context.colors.textPrimary
                        : context.colors.textSecondary,
                  ),
                ),
              ),
            );
          }),
        ),
        // X times per week stepper
        if (_frequency == FrequencyType.timesPerWeek) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.primarySurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_timesPerWeek ${_timesPerWeek == 1 ? "time" : "times"} per week',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    _StepperButton(
                      icon: LucideIcons.minus,
                      onTap: () {
                        if (_timesPerWeek > 1) setState(() => _timesPerWeek--);
                      },
                    ),
                    const SizedBox(width: 6),
                    _StepperButton(
                      icon: LucideIcons.plus,
                      onTap: () {
                        if (_timesPerWeek < 7) setState(() => _timesPerWeek++);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Section: Duration / Goal ────────────────────────────────────────────

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Duration or Goal'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: context.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontFamily: 'Inter',
                      color: context.colors.textSecondary,
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Container(width: 1, height: 44, color: context.colors.border),
              // Unit selector
              PopupMenuButton<String>(
                color: context.colors.primarySurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (val) {
                  if (val == '__custom__') {
                    _addCustomUnit();
                  } else {
                    setState(() => _durationUnit = val);
                  }
                },
                itemBuilder: (_) => [
                  ...userDurationUnits.map((u) => PopupMenuItem(
                        value: u,
                        child: Text(
                          u,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: _durationUnit == u
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: _durationUnit == u
                                ? context.colors.textPrimary
                                : context.colors.textSecondary,
                          ),
                        ),
                      )),
                  PopupMenuItem(
                    value: '__custom__',
                    child: Text(
                      '+ Custom unit',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Text(
                        _durationUnit,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.chevronsUpDown,
                          size: 14, color: context.colors.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section: Reminder ───────────────────────────────────────────────────

  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Reminder'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Remind me',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
              Switch(
                value: _reminderEnabled,
                onChanged: (v) => setState(() => _reminderEnabled = v),
                activeThumbColor: Colors.white,
                activeTrackColor: context.colors.primaryAccent,
                inactiveThumbColor: context.colors.textSecondary,
                inactiveTrackColor: context.colors.secondarySurface,
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        if (_reminderEnabled) ...[
          const SizedBox(height: 10),
          // Time picker row
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.clock, size: 18, color: context.colors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _formatTime(_reminderTime),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight,
                      size: 16, color: context.colors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Repeat toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.primarySurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Repeat reminder daily',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                Switch(
                  value: _repeatReminder,
                  onChanged: (v) => setState(() => _repeatReminder = v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: context.colors.primaryAccent,
                  inactiveThumbColor: context.colors.textSecondary,
                  inactiveTrackColor: context.colors.secondarySurface,
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Keep reminding until the habit is actually ticked off.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.primarySurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Keep reminding until done',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Follow-ups stop as soon as you tick it off',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _repeatUntilDone,
                      onChanged: (v) => setState(() => _repeatUntilDone = v),
                      activeThumbColor: Colors.white,
                      activeTrackColor: context.colors.primaryAccent,
                      inactiveThumbColor: context.colors.textSecondary,
                      inactiveTrackColor: context.colors.secondarySurface,
                      trackOutlineColor:
                          WidgetStateProperty.all(Colors.transparent),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                if (_repeatUntilDone) ...[
                  const SizedBox(height: 14),
                  _DropdownRow(
                    icon: LucideIcons.repeat,
                    label: 'Every',
                    value: _repeatIntervalMinutes == 60
                        ? '1 hour'
                        : '$_repeatIntervalMinutes min',
                    onTap: () => _showRepeatIntervalPicker(),
                  ),
                  const SizedBox(height: 10),
                  _DropdownRow(
                    icon: LucideIcons.bellRing,
                    label: 'Up to',
                    value: _repeatMaxCount == 1
                        ? '1 follow-up'
                        : '$_repeatMaxCount follow-ups',
                    onTap: () => _showRepeatCountPicker(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showRepeatIntervalPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimplePickerSheet<int>(
        title: 'Remind again every',
        items: const [15, 30, 60],
        labelFn: (m) => m == 60 ? '1 hour' : '$m minutes',
        idFn: (m) => '$m',
        selectedId: '$_repeatIntervalMinutes',
        onSelected: (m) => setState(() => _repeatIntervalMinutes = m),
      ),
    );
  }

  void _showRepeatCountPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimplePickerSheet<int>(
        title: 'Number of follow-ups',
        items: const [1, 2, 3, 4, 5],
        labelFn: (c) => c == 1 ? '1 follow-up' : '$c follow-ups',
        idFn: (c) => '$c',
        selectedId: '$_repeatMaxCount',
        onSelected: (c) => setState(() => _repeatMaxCount = c),
      ),
    );
  }

  // ── Section: Cover Image ────────────────────────────────────────────────

  Widget _buildCoverImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Cover Image'),
        const SizedBox(height: 6),
        Text(
          'Optional — shown on your Today\'s Focus card.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              ...presetCoverImages.map((url) {
                final sel = _coverImageUrl == url;
                return GestureDetector(
                  onTap: () => setState(() => _coverImageUrl = sel ? null : url),
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: sel ? context.colors.primaryAccent : context.colors.border,
                        width: sel ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: context.colors.secondarySurface,
                          child: Icon(LucideIcons.image,
                              color: context.colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Custom upload (shows the uploaded image once set)
              if (_coverImageUrl != null && _isUploadedCover(_coverImageUrl!))
                GestureDetector(
                  onTap: _uploadingCover ? null : _pickCoverImage,
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: context.colors.primaryAccent, width: 2.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: context.colors.secondarySurface,
                          child: Icon(LucideIcons.image,
                              color: context.colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _uploadingCover ? null : _pickCoverImage,
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: context.colors.primarySurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: _uploadingCover
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.imagePlus,
                                size: 22, color: context.colors.textSecondary),
                            SizedBox(height: 6),
                            Text(
                              'Upload',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section: Location ───────────────────────────────────────────────────

  void _onLocationSearchChanged(String query) {
    _locationDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _locationResults = []);
      return;
    }
    _locationDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _locationSearching = true);
      final results = await LocationService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _locationResults = results;
          _locationSearching = false;
        });
      }
    });
  }

  void _selectPlace(PlaceResult place) {
    setState(() {
      _locationName = place.shortName;
      _locationLat = place.lat;
      _locationLng = place.lng;
      _locationResults = [];
      _locationSearchController.clear();
    });
  }

  void _clearLocation() {
    setState(() {
      _locationName = null;
      _locationLat = null;
      _locationLng = null;
      _locationResults = [];
      _locationSearchController.clear();
    });
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Location'),
        const SizedBox(height: 6),
        Text(
          'Optional — must physically reach this place to mark complete.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 12),
        // Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Require location check-in',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
              Switch(
                value: _locationEnabled,
                onChanged: (v) => setState(() {
                  _locationEnabled = v;
                  if (!v) _clearLocation();
                }),
                activeThumbColor: Colors.white,
                activeTrackColor: context.colors.primaryAccent,
                inactiveThumbColor: context.colors.textSecondary,
                inactiveTrackColor: context.colors.secondarySurface,
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        if (_locationEnabled) ...[
          const SizedBox(height: 10),
          if (_locationLat != null) ...[
            // Selected place chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.primaryAccent),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.mapPin,
                      size: 18, color: context.colors.primaryAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locationName ?? '',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Within 200 m to check in',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _clearLocation,
                    child: Icon(LucideIcons.x,
                        size: 18, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Search field
            Container(
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: _locationSearching
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.textSecondary,
                            ),
                          )
                        : Icon(LucideIcons.search,
                            size: 18, color: context.colors.textSecondary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _locationSearchController,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: context.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for a gym, place…',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: context.colors.textSecondary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: InputBorder.none,
                      ),
                      onChanged: _onLocationSearchChanged,
                    ),
                  ),
                ],
              ),
            ),
            if (_locationResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.colors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _locationResults.length; i++) ...[
                      if (i > 0)
                        Divider(
                            height: 1,
                            thickness: 1,
                            color: context.colors.border),
                      GestureDetector(
                        onTap: () => _selectPlace(_locationResults[i]),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          child: Row(
                            children: [
                              Icon(LucideIcons.mapPin,
                                  size: 16,
                                  color: context.colors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _locationResults[i].shortName,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: context.colors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      _locationResults[i].displayName,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        color: context.colors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  // ── Section: Accountability (Friend Link) ───────────────────────────────

  Widget _buildAccountabilitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Accountability'),
        const SizedBox(height: 6),
        Text(
          'Optional — link this habit to a friend\'s habit.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Link this habit to a friend',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
              Switch(
                value: _linkToFriend,
                onChanged: (v) => setState(() {
                  _linkToFriend = v;
                  if (!v) {
                    _linkedFriendId = null;
                    _linkedFriendHabitId = null;
                  }
                }),
                activeThumbColor: Colors.white,
                activeTrackColor: context.colors.primaryAccent,
                inactiveThumbColor: context.colors.textSecondary,
                inactiveTrackColor: context.colors.secondarySurface,
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        if (_linkToFriend) ...[
          const SizedBox(height: 10),
          // Friend selector
          _DropdownRow(
            label: 'Select friend',
            icon: LucideIcons.users,
            value: _linkedFriendName,
            onTap: () => _showFriendPicker(),
          ),
          if (_linkedFriendId != null) ...[
            const SizedBox(height: 10),
            // Habit selector
            _DropdownRow(
              label: 'Select their habit',
              icon: LucideIcons.link2,
              value: _linkedFriendHabitName,
              onTap: () => _showFriendHabitPicker(),
            ),
            if (_linkedFriendHabitId != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.bellRing,
                        size: 15, color: context.colors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'When ${_linkedFriendName ?? ''} starts ${_linkedFriendHabitName ?? ''}, you\'ll be reminded to begin "${_nameController.text.isEmpty ? 'this habit' : _nameController.text}".',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  void _showFriendPicker() {
    final friends = ref.read(friendsProvider).valueOrNull?.friends ?? const <Friend>[];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimplePickerSheet<Friend>(
        title: 'Select Friend',
        items: friends,
        labelFn: (f) => f.name,
        subLabelFn: (f) => f.username,
        selectedId: _linkedFriendId,
        idFn: (f) => f.id,
        onSelected: (f) => setState(() {
          _linkedFriendId = f.id;
          _linkedFriendName = f.name;
          _linkedFriendHabitId = null; // reset habit when friend changes
          _linkedFriendHabitName = null;
        }),
      ),
    );
  }

  Future<void> _showFriendHabitPicker() async {
    final friendId = _linkedFriendId;
    if (friendId == null) return;
    final habits = await ref.read(friendHabitsProvider(friendId).future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimplePickerSheet<Habit>(
        title: 'Select Their Habit',
        items: habits,
        labelFn: (h) => h.name,
        selectedId: _linkedFriendHabitId,
        idFn: (h) => h.id,
        onSelected: (h) => setState(() {
          _linkedFriendHabitId = h.id;
          _linkedFriendHabitName = h.name;
        }),
      ),
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────────

  Widget _buildDivider() => Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Divider(color: context.colors.border, height: 1, thickness: 1),
      );

  Widget _buildSaveButton(double bottomPadding) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _selectedCategory.isNotEmpty;
    return Container(
      color: context.colors.background,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + bottomPadding),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canSave ? context.colors.primaryAccent : context.colors.secondarySurface,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
            'Create Habit',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: canSave ? Colors.white : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets (private to this file)
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDashed;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.isSelected,
    this.isDashed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primaryAccent : context.colors.primarySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? context.colors.primaryAccent
                : isDashed
                    ? context.colors.textSecondary
                    : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected
                ? Colors.white
                : isDashed
                    ? context.colors.textSecondary
                    : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HabitTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _HabitTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primaryAccent : context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? context.colors.primaryAccent : context.colors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20,
                color: isSelected ? context.colors.onAccent : context.colors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.75)
                          : context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(LucideIcons.check, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.colors.secondarySurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: context.colors.textPrimary),
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final VoidCallback onTap;

  const _DropdownRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight:
                      value != null ? FontWeight.w500 : FontWeight.normal,
                  color: value != null
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                ),
              ),
            ),
            Icon(LucideIcons.chevronsUpDown,
                size: 14, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic picker sheet
// ---------------------------------------------------------------------------

class _SimplePickerSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelFn;
  final String Function(T)? subLabelFn;
  final String? selectedId;
  final String Function(T) idFn;
  final ValueChanged<T> onSelected;

  const _SimplePickerSheet({
    required this.title,
    required this.items,
    required this.labelFn,
    this.subLabelFn,
    required this.selectedId,
    required this.idFn,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              )),
          const SizedBox(height: 14),
          ...items.map((item) {
            final sel = idFn(item) == selectedId;
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onSelected(item);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color:
                      sel ? context.colors.primaryAccent : context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: sel ? context.colors.primaryAccent : context.colors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labelFn(item),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: sel ? Colors.white : context.colors.textPrimary,
                            ),
                          ),
                          if (subLabelFn != null)
                            Text(
                              subLabelFn!(item),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: sel
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : context.colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (sel)
                      const Icon(LucideIcons.check, size: 16, color: Colors.white),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon picker sheet
// ---------------------------------------------------------------------------

class _IconPickerSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onPick;

  const _IconPickerSheet({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Choose an icon',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              )),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _iconOptions.map((key) {
                  final sel = key == current;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onPick(key);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: sel
                            ? context.colors.primaryAccent
                            : context.colors.primarySurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel
                              ? context.colors.primaryAccent
                              : context.colors.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        habitIconData(key),
                        size: 24,
                        color: sel ? context.colors.onAccent : context.colors.textPrimary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic input sheet (for custom category / custom unit)
// ---------------------------------------------------------------------------

Future<String?> _showInputSheet({
  required BuildContext context,
  required String title,
  required String hint,
  required TextEditingController controller,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                )),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.border),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: context.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    color: context.colors.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Add',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
