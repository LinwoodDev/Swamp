import 'dart:io';

void main(List<String> args) {
  final version = args.elementAtOrNull(0) ?? _findCurrentDartVersion();
  updateDockerfile(version);
  updateServerPubspec(version);
}

String _findCurrentDartVersion() {
  final result = Process.runSync('dart', ['--version'], runInShell: true);
  if (result.exitCode != 0) {
    throw Exception('Failed to get Dart version: ${result.stderr}');
  }
  final output = result.stdout.toString(); // dart --version outputs to stderr
  final regex = RegExp(r'Dart SDK version: (\d+\.\d+\.\d+)');
  final match = regex.firstMatch(output);
  if (match != null) {
    return match.group(1)!;
  } else {
    throw Exception('Could not parse Dart version from output: $output');
  }
}

void updateDockerfile(String version) {
  final file = File('Dockerfile');
  if (!file.existsSync()) {
    print('Dockerfile not found at ${file.path}');
    return;
  }
  var content = file.readAsStringSync();
  final regex = RegExp(r'FROM dart:[\d\.]+ AS build');
  if (regex.hasMatch(content)) {
    content = content.replaceAll(regex, 'FROM dart:$version AS build');
    file.writeAsStringSync(content);
    print('Updated Dockerfile to $version');
  } else {
    print('Could not find dart version in Dockerfile');
  }
}

void updateServerPubspec(String version) {
  final file = File('server/pubspec.yaml');
  if (!file.existsSync()) {
    print('server/pubspec.yaml not found at ${file.path}');
    return;
  }
  var content = file.readAsStringSync();
  final regex = RegExp(r'sdk: \^[\d\.]+');
  if (regex.hasMatch(content)) {
    content = content.replaceAll(regex, 'sdk: ^$version');
    file.writeAsStringSync(content);
    print('Updated server/pubspec.yaml to $version');
  } else {
    print('Could not find sdk version in server/pubspec.yaml');
  }
}
