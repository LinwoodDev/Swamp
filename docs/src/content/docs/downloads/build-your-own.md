---
title: "Build your own"
---

![Nightly release version](https://img.shields.io/badge/dynamic/yaml?color=1CC637&label=Nightly&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FLinwoodDev%2FSwamp%2Fnightly%2Fserver%2Fpubspec.yaml&style=for-the-badge)

It is very easy to build the binaries.

Install dart and build the server using:

```bash
cd server
dart pub get
dart compile exe
```

The executable can be found in `bin/swamp.exe`.
