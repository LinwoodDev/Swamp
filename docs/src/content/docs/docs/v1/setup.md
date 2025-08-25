---
title: Setup
---

## Get the server

To get started with Swamp, first download the latest release from the [downloads page](/downloads/).
Docker is the recommended way to run the server, but you can also download the binaries for your platform.

## Run the server

Just run the server and it will start listening on port `8080` by default.
To change the port, use the `PORT` environment variable.

Please note that you need applications uses http/https ports, so you need to specify a the port (http: `80`, https: `443`) if you want to use these ports or use a reverse proxy like nginx or apache.

To run the server in https mode, you need to create a `certs` folder in the same directory (make sure to add a volume if you are using docker) and add your `server.key` (private key) and `server.crt` (certificate) files there.
