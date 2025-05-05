---
title: Introduction
---

> Welcome to Swamp, the universal simple web-socket application messaging protocol

## What is Swamp?

Swamp is a simple, fast, and secure web-socket application messaging protocol. It is designed to be easy to use and implement, while also being flexible enough to support a wide range of applications. It uses a room based system to allow grouping of users and messages.

You can think about Swamp as a hotel with rooms. If you connect to the swamp web socket server, you are in the lobby.
Now you can go to a room or create a new room. To go to a room you need the room id.
If you create a room, you will be the owner of the room and get a room id to share with others.
The room id is a random byte array that is generated when you create a room.

In this room everyone can send messages to each other. You can also send private messages to other users in the room. These messages could be anything, it is also recommended to use end to end encryption for these but the protocol does not enforce this.
You can also ask the swamp server how many users are in the room and get the player id of each user that will be generated when joining the room.
If the owner of the room leaves, the room will be closed and all users will be disconnected.

Simple usecases for Swamp could be a temporary chat room, a web minigame or a collaborative document editor.

## How to use Swamp

Swamp can be either used as a simple binary to run on your server or as a library in your own project.
The server is written in Dart and can be run on any platform that supports Dart. The library is also written in Dart and can be used in any Dart or Flutter project.
