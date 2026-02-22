import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../content/providers/content_providers.dart';
import '../../../database/app_database.dart';
import '../../learn/providers/deck_review_provider.dart';
import '../../library/providers/library_provider.dart';
import '../../progression/providers/progression_provider.dart';
import '../../srs/providers/srs_provider.dart';
import '../../today/providers/today_session_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Setting? _settings;
  bool _loading = true;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = ref.read(appDatabaseProvider);
    final settings = await db.settingsDao.getSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _loading = false;
      });
    }
  }

  Future<void> _updateSetting(SettingsCompanion update) async {
    final db = ref.read(appDatabaseProvider);
    await db.settingsDao.upsertSettings(update);
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _SectionHeader(title: 'Display'),
                ListTile(
                  title: const Text('Note display style'),
                  subtitle: Text(_noteDisplayLabel(
                      _settings?.noteDisplayStyle ?? 'auto')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showNoteDisplayPicker(),
                ),
                ListTile(
                  title: const Text('Theme'),
                  subtitle: Text(
                      _themeLabel(_settings?.themeMode ?? 'system')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemePicker(),
                ),
                SwitchListTile(
                  title: const Text('Show notation'),
                  subtitle: const Text('Display staff notation in questions'),
                  value: _settings?.showNotation ?? true,
                  onChanged: (value) {
                    _updateSetting(
                      SettingsCompanion(showNotation: Value(value)),
                    );
                  },
                ),
                ListTile(
                  title: const Text('Answer input'),
                  subtitle: Text(_answerInputLabel(
                      _settings?.answerInputMode ?? 'multipleChoice')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAnswerInputPicker(),
                ),
                SwitchListTile(
                  title: const Text('Show interval hints'),
                  subtitle:
                      const Text('Show next review time on rating buttons'),
                  value: _settings?.showIntervalHints ?? true,
                  onChanged: (value) {
                    _updateSetting(
                      SettingsCompanion(showIntervalHints: Value(value)),
                    );
                  },
                ),
                const Divider(),
                const _SectionHeader(title: 'Audio'),
                SwitchListTile(
                  title: const Text('Auto-play audio'),
                  subtitle:
                      const Text('Automatically play audio for ear training'),
                  value: _settings?.autoPlayAudio ?? false,
                  onChanged: (value) {
                    _updateSetting(
                      SettingsCompanion(autoPlayAudio: Value(value)),
                    );
                  },
                ),
                const Divider(),
                const _SectionHeader(title: 'Session'),
                ListTile(
                  title: const Text('New cards per day'),
                  subtitle: const Text('Max new items to introduce daily'),
                  trailing: Text(
                    '${_settings?.newCardsPerDay ?? 5}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  onTap: () => _showNewCardsPerDayPicker(),
                ),
                ListTile(
                  title: const Text('Deck drill count'),
                  subtitle: const Text('Default number of cards for drills'),
                  trailing: Text(
                    '${_settings?.deckDrillCount ?? 10}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  onTap: () => _showDeckDrillCountPicker(),
                ),
                ListTile(
                  title: const Text('Deck drill hardness'),
                  subtitle: const Text('How strict “Hard” drill selection is'),
                  trailing: Text(
                    _hardnessLabel(
                        _settings?.deckHardnessLevel ?? 'medium'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  onTap: () => _showDeckHardnessPicker(),
                ),
                ListTile(
                  title: const Text('SRS retention target'),
                  subtitle:
                      const Text('Target recall rate for spaced repetition'),
                  trailing: Text(
                    '${((_settings?.srsDesiredRetention ?? 0.9) * 100).round()}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                  onTap: () => _showRetentionPicker(),
                ),
                ListTile(
                  title: const Text('Test time limit'),
                  trailing: Text(
                    '${(_settings?.drillTimeLimitSeconds ?? 120) ~/ 60} min',
                    style: theme.textTheme.bodyLarge,
                  ),
                  onTap: () => _showTimeLimitPicker(),
                ),
                const Divider(),
                const _SectionHeader(title: 'Data'),
                ListTile(
                  title: Text(
                    'Reset progress',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Clears review history, schedules, and tier progress',
                  ),
                  trailing: _resetting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onTap: _resetting ? null : _confirmResetProgress,
                ),
              ],
            ),
    );
  }

  String _noteDisplayLabel(String style) {
    return switch (style) {
      'sharp' => 'Sharps (C#, D#, F#...)',
      'flat' => 'Flats (Db, Eb, Gb...)',
      _ => 'Auto (context-dependent)',
    };
  }

  String _themeLabel(String mode) {
    return switch (mode) {
      'light' => 'Light',
      'dark' => 'Dark',
      _ => 'System',
    };
  }

  void _showNoteDisplayPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final style in ['auto', 'sharp', 'flat'])
              ListTile(
                title: Text(_noteDisplayLabel(style)),
                trailing: (_settings?.noteDisplayStyle ?? 'auto') == style
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(noteDisplayStyle: Value(style)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ['system', 'light', 'dark'])
              ListTile(
                title: Text(_themeLabel(mode)),
                trailing: (_settings?.themeMode ?? 'system') == mode
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(themeMode: Value(mode)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showRetentionPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final retention in [0.8, 0.85, 0.9, 0.95])
              ListTile(
                title: Text('${(retention * 100).round()}%'),
                trailing:
                    (_settings?.srsDesiredRetention ?? 0.9) == retention
                        ? const Icon(Icons.check)
                        : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(
                        srsDesiredRetention: Value(retention)),
                  );
                  ref
                      .read(srsRetentionProvider.notifier)
                      .set(retention);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _hardnessLabel(String value) {
    return switch (value) {
      'strict' => 'Strict',
      'wide' => 'Wide',
      _ => 'Medium',
    };
  }

  void _showDeckHardnessPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final level in ['strict', 'medium', 'wide'])
              ListTile(
                title: Text(_hardnessLabel(level)),
                trailing:
                    (_settings?.deckHardnessLevel ?? 'medium') == level
                        ? const Icon(Icons.check)
                        : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(
                      deckHardnessLevel: Value(level),
                    ),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDeckDrillCountPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final count in [5, 10, 15, 20, 30])
              ListTile(
                title: Text('$count cards'),
                trailing: (_settings?.deckDrillCount ?? 10) == count
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(deckDrillCount: Value(count)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _answerInputLabel(String mode) {
    return switch (mode) {
      'keyboard' => 'Piano keyboard',
      'none' => 'None (self-reveal)',
      _ => 'Multiple choice',
    };
  }

  void _showAnswerInputPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ['multipleChoice', 'keyboard', 'none'])
              ListTile(
                title: Text(_answerInputLabel(mode)),
                trailing:
                    (_settings?.answerInputMode ?? 'multipleChoice') == mode
                        ? const Icon(Icons.check)
                        : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(answerInputMode: Value(mode)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showNewCardsPerDayPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final count in [3, 5, 10, 15, 20, 25, 30, 40, 50])
              ListTile(
                title: Text('$count new cards'),
                trailing:
                    (_settings?.newCardsPerDay ?? 5) == count
                        ? const Icon(Icons.check)
                        : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(newCardsPerDay: Value(count)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showTimeLimitPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final seconds in [60, 90, 120, 180, 300])
              ListTile(
                title: Text('${seconds ~/ 60} minute${seconds > 60 ? 's' : ''}'),
                trailing:
                    (_settings?.drillTimeLimitSeconds ?? 120) == seconds
                        ? const Icon(Icons.check)
                        : null,
                onTap: () {
                  _updateSetting(
                    SettingsCompanion(drillTimeLimitSeconds: Value(seconds)),
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmResetProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This clears all review history, schedules, and progression stats. '
          'Your decks and content stay intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await ref.read(contentRepositoryProvider).resetProgress();
      ref.invalidate(exerciseCountsProvider);
      ref.invalidate(exerciseGroupCountsProvider);
      ref.invalidate(deckTreeStatsProvider);
      ref.invalidate(tiersByTopicProvider);
      ref.invalidate(todaySessionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress reset.')),
      );
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
