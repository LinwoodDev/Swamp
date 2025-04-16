---
title: Selfhosting
---

![Nightly release version](https://img.shields.io/badge/dynamic/yaml?color=1CC637&label=Nightly&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FLinwoodDev%2FSwamp%2Fnightly%2Fserver%2Fpubspec.yaml&style=for-the-badge)

It is very easy to host your own swamp server.

## Simple server

Install flutter and build the app using:

```bash
cd server
dart pub get
dart build web
```

The executable can be found in `bin/swamp.exe`.

## Docker

### Dockerhub

You can pull the latest version of the image from Dockerhub using:

```bash
docker pull linwooddev/swamp
```

The tags are:

- `:latest` is the current main branch
- `:dev` is the current develop branch
- `:stable` is the latest stable release (like the git tag)
- `:nightly` is the latest nightly release (like the git tag)
- Tags starting with `:v` are releases

Start the server using: `docker run -p 8080:80 -d linwooddev/swamp`.

### Selfbuilding

Clone the repository and build thHe `Dockerfile` using: `docker build -t linwood-swamp`.
Start the server using: `docker run -p 8080:80 -d linwood-swamp`.
