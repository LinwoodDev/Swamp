import 'dart:io';

import 'package:args/args.dart';
import 'package:intl/intl.dart';

Future<void> main(List<String> args) async {
  var parser = ArgParser();

  var results = parser.parse(args);

  var version = results.rest.isEmpty ? null : results.rest[0];
  // Update the version in the pubspec.yaml
  File pubspec = File('server/pubspec.yaml');
  String content = await pubspec.readAsString();
  // Get last version from pubspec.yaml
  RegExp exp = RegExp(r'version:\s(?<version>.+)');
  var match = exp.firstMatch(content);
  if (match == null) {
    print('Could not find the version in the pubspec.yaml');
    exit(1);
  }
  var lastVersion = match.namedGroup('version') ?? '';
  version ??= lastVersion;

  // Update the version in the pubspec.yaml
  content = content.replaceAll(exp, 'version: $version');

  await pubspec.writeAsString(content);
  print(
      'Updating the version in the pubspec.yaml from $lastVersion to $version');

  // Update api
  final apiPubspec = File('api/pubspec.yaml');
  var apiContent = await apiPubspec.readAsString();
  apiContent =
      apiContent.replaceAll(RegExp(r'version: .+'), 'version: $version');
  await apiPubspec.writeAsString(apiContent);
  print(
      'Updating the version in the api pubspec.yaml from $lastVersion to $version');

  // Run dart pub get in server directory
  await Process.run('dart', ['pub', 'get'],
      workingDirectory: 'server', runInShell: true);

  print('Successfully updated!');
}

bool isPreRelease(String version) {
  return version.contains('-');
}

Future<void> updateChangelog(String version, String changelog) async {
  var currentDate = DateTime.now();
  final changelogRegex = RegExp(r'<!--ENTER CHANGELOG HERE-->');
  var dateString = DateFormat('yyyy-MM-dd').format(currentDate);
  var file = File('CHANGELOG.md');
  var content = await file.readAsString();
  content = content.replaceAll(changelogRegex,
      '<!--ENTER CHANGELOG HERE-->\r\n\r\n## $version ($dateString)\r\n\r\n$changelog');
  await file.writeAsString(content);
  print('Successfully updated docs for version $version');
}
