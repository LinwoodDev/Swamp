import 'dart:io';

final _versionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*)?(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$',
);
final _pubspecVersion = RegExp(r'^version: .+$', multiLine: true);
final _unreleased = RegExp(r'^## Unreleased[ \t]*$', multiLine: true);

void main(List<String> args) {
  try {
    if (args.isEmpty || args.length == 1 && args.single == '--help') {
      stdout.writeln('Usage (from the repository root):\n'
          '  dart tools/set_version.dart <version> [--no-changelog]\n'
          '  dart tools/set_version.dart --changelog\n'
          '  dart tools/set_version.dart --notes <version|Unreleased>');
      return;
    }
    final changelogFile = File('CHANGELOG.md');
    final changelog = changelogFile.readAsStringSync().replaceAll('\r\n', '\n');
    if (args.length == 2 && args.first == '--notes') {
      stdout.write(releaseNotes(changelog, args.last));
      return;
    }
    final updateChangelog = !args.contains('--no-changelog');
    final versions = args.where((arg) => !arg.startsWith('--')).toList();
    if (versions.length > 1 ||
        args.any((arg) =>
            arg.startsWith('--') &&
            arg != '--changelog' &&
            arg != '--no-changelog') ||
        args.contains('--changelog') && args.contains('--no-changelog') ||
        versions.isEmpty && !args.contains('--changelog')) {
      throw FormatException('Expected an explicit version or --changelog.');
    }

    final server = File('server/pubspec.yaml');
    final api = File('api/pubspec.yaml');
    final serverContent = server.readAsStringSync();
    final apiContent = api.readAsStringSync();
    final match = _pubspecVersion.firstMatch(serverContent);
    if (match == null || !_pubspecVersion.hasMatch(apiContent)) {
      throw FormatException('Missing pubspec version.');
    }
    final current = match.group(0)!.substring('version: '.length).trim();
    final version = versions.isEmpty ? current : versions.single;
    if (!_versionPattern.hasMatch(version)) {
      throw FormatException('Provide an explicit semantic version: $version');
    }
    if (!updateChangelog) {
      if (version == current) {
        throw FormatException('The next version must differ from $current.');
      }
      server.writeAsStringSync(
          serverContent.replaceFirst(_pubspecVersion, 'version: $version'));
      api.writeAsStringSync(
          apiContent.replaceFirst(_pubspecVersion, 'version: $version'));
      stdout.writeln('Updated $current to $version.');
      return;
    }
    if (RegExp('^## ${RegExp.escape(version)} \\(', multiLine: true)
        .hasMatch(changelog)) {
      throw FormatException('Changelog already contains version $version.');
    }
    final notes = releaseNotes(changelog, 'Unreleased');
    final heading = _unreleased.firstMatch(changelog)!;
    final end = nextSection(changelog, heading.end);
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final updated = changelog.replaceRange(heading.start, end,
        '## Unreleased\n\n## $version ($date)\n\n$notes\n\n');

    // Validate all inputs before writing any release files.
    server.writeAsStringSync(
        serverContent.replaceFirst(_pubspecVersion, 'version: $version'));
    api.writeAsStringSync(
        apiContent.replaceFirst(_pubspecVersion, 'version: $version'));
    changelogFile.writeAsStringSync(updated.trimRight());
    stdout.writeln('Updated $current to $version and finalized release notes.');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

int nextSection(String changelog, int start) {
  final next =
      RegExp(r'^## ', multiLine: true).firstMatch(changelog.substring(start));
  return next == null ? changelog.length : start + next.start;
}

String releaseNotes(String changelog, String version) {
  final headings = version == 'Unreleased'
      ? _unreleased
      : RegExp('^## ${RegExp.escape(version)} \\([^\\n]+\\)[ \\t]*\$',
          multiLine: true);
  final matches = headings.allMatches(changelog).toList();
  if (matches.length != 1) {
    throw FormatException(
        'Expected exactly one changelog section for $version.');
  }
  final heading = matches.single;
  final notes = changelog
      .substring(heading.end, nextSection(changelog, heading.end))
      .trim();
  if (notes.isEmpty) throw FormatException('No release notes for $version.');
  return notes;
}
