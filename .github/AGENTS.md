# Agent Notes

This repo is a Flutter app for managing Linux servers over SSH with a visual UI.

## Start Here
- Product overview, architecture, and scope: [README.md](README.md)

## Build and Test (common)
- Fetch deps: `flutter pub get`
- Analyze: `flutter analyze`
- Run tests: `flutter test`

## Codegen
- Isar codegen uses build_runner; see [pubspec.yaml](pubspec.yaml).
- Typical command: `flutter pub run build_runner build`

## Code Layout
- App entry point: [lib/main.dart](lib/main.dart)
- Dependency injection registration: [lib/injection.dart](lib/injection.dart)
- UI: [lib/view/](lib/view/)
- Controllers: [lib/controller/](lib/controller/)
- Domain logic: [lib/logic/](lib/logic/)
- Data layer (DAOs, entities, repositories, services): [lib/model/](lib/model/)

## Conventions
- Follow the existing file naming style within each directory (mixed PascalCase and snake_case).
- Keep the 3-layer separation described in [README.md](README.md).
