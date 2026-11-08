# Contribution guide

There are many ways to contribute to this project.
Thanks to everyone who has contributed!
If you have any questions, please contact me at [contact@linwood.dev](mailto:contact@linwood.dev).

There is a matrix server for this project [here](https://linwood.dev/matrix) and a discord server [here](https://discord.linwood.dev).

Please follow the [Code of Conduct](https://swamp.linwood.dev/code-of-conduct).

## Give feedback

The best way to give feedback is to open an issue on GitHub.
Please report any bug you find [here](https://github.com/LinwoodDev/Swamp/issues/new?assignees=CodeDoctorDE&labels=bug%2Ctriage&template=bug_report.yml&title=%5BBug%5D%3A+).

If you have a feature that you would like to see added, please open an issue [here](https://github.com/LinwoodDev/Swamp/issues/new?assignees=CodeDoctorDE&labels=enhancement%2Ctriage&template=feature_request.yml&title=%5BFeature+request%5D%3A+).

## Test nightly builds

Nightly builds are not production ready and need to be tested.
Please report any bugs in the github issues section.

Read more about it [here](https://swamp.linwood.dev/nightly).

## Write documentation

Documentation is important for users to understand the program and its features.
The documentation is written in markdown, a simple markup language. It can be found in the `docs` folder.

To start, please install [pnpm](https://pnpm.io/installation).

Get started by running:

```bash
cd docs
pnpm install
pnpm start
```

All stable documentation can be found in the `versioned_docs` folder.

Fork the project and create a pull request to add your documentation to the `develop` branch.

## Translate

Crowdin is a service that allows you to translate the documentation and the app.
Click [here](https://translate.linwood.dev/swamp) to see the project and start translating.
If you have a new language to add, please contact me.

## Code

This project is written in [Dart](https://dart.dev/).
The server source code can be found in the `server` folder.

To get started, run:

```bash
cd app
dart pub get
dart run
```

Fork the project and create a pull request to add your code to the `develop` branch.

## Changelog and releases

Add user-facing changes under `## Unreleased` in `CHANGELOG.md`. Keep this
section present, even when empty, and do not add a trailing newline to the file.
Include features and fixes that affect users; omit documentation and internal
changes such as dependency updates, CI, refactoring, and development tooling.

Run the **Release** workflow manually on the branch to publish. It releases
that branch's current version and requires an explicit `next_version` for
subsequent development. For example, when the current version is `0.2.0`,
enter `0.2.1` to publish `v0.2.0` and then continue development at `0.2.1`.
Enable `stable` for a stable release; releases from `main` are always stable.

The workflow finalizes the Unreleased notes, keeps an empty Unreleased section,
tags the release commit, and updates the server and API to `next_version`.
Both versions are checked locally before commits and the tag are pushed.
Release notes come from the published version's changelog section. The existing
build and post-release workflows attach artifacts and update stable/nightly tags.
The `CI_PAT` repository secret is required so publishing triggers those workflows.

For local preparation, use an explicit version:

```bash
dart tools/set_version.dart 0.2.0
```

To finalize notes for the current version or change only the development version:

```bash
dart tools/set_version.dart --changelog
dart tools/set_version.dart 0.2.1 --no-changelog
```

Empty notes and duplicate release sections are rejected before release files
are changed. To extract notes without changing files:

```bash
dart tools/set_version.dart --notes 0.2.0
```
