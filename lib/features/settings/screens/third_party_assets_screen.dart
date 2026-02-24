import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThirdPartyAssetsScreen extends StatelessWidget {
  const ThirdPartyAssetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Third-party software & assets')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader(title: 'Bundled Assets'),
          ListTile(
            title: const Text('Piano SoundFont (piano.sf2)'),
            subtitle: Text(
              'Bundled as piano.sf2 for app playback. Embedded metadata '
              'identifies the SoundFont as "Upright piano KW (small)".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Original SoundFont: UprightPianoKW-small-20190703.sf2'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Source project: FreePats (Upright piano KW)'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('License: CC0 1.0 Universal (public domain dedication)'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Source: http://freepats.zenvoid.org/Piano/acoustic-grand-piano.html#UprightKW',
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'This app bundles a CC0 soundfont for playback. Attribution is '
              'included here for provenance (CC0 does not require attribution). '
              'See bundled notices and the CC0 legal text below.',
            ),
          ),
          ListTile(
            title: const Text('View bundled asset notices'),
            subtitle: const Text('Provenance, upstream source, and packaging notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _AssetTextScreen(
                  title: 'Bundled Asset Notices',
                  assetPath: 'assets/licenses/third_party_notices.md',
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('View upstream readme'),
            subtitle: const Text('FreePats Upright piano KW readme'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _AssetTextScreen(
                  title: 'Upright piano KW Readme',
                  assetPath: 'assets/licenses/upright_piano_kw_readme.txt',
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('View CC0 1.0 legal text'),
            subtitle: const Text('Creative Commons CC0 1.0 Universal'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _AssetTextScreen(
                  title: 'CC0 1.0 Universal',
                  assetPath: 'assets/licenses/upright_piano_kw_cc0.txt',
                ),
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader(title: 'Open-source Packages'),
          ListTile(
            title: const Text('View package licenses'),
            subtitle: const Text('Flutter and Dart package license notices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Jazz Piano Tools',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssetTextScreen extends StatelessWidget {
  final String title;
  final String assetPath;

  const _AssetTextScreen({required this.title, required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                'Failed to load $assetPath\n\n${snapshot.error}',
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(snapshot.data ?? ''),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
