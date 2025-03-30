---
title: Selfhosting
---

![Nightly release version](https://img.shields.io/badge/dynamic/yaml?color=1CC637&label=Nightly&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FLinwoodDev%2FSwamp%2Fnightly%2Fserver%2Fpubspec.yaml&style=for-the-badge)

It is very easy to host your own butterfly web server.

## Simple server

Install flutter and build the app using:

```bash
cd server
dart pub get
dart compile exe bin/swamp.dart
```

The executable can be found in `bin/swamp.exe`.

## Docker

Clone the repository and build the `Dockerfile` using: `docker build -t linwood-swamp`.
Start the server using: `docker run -p 8080:80 -d linwood-swamp`.
