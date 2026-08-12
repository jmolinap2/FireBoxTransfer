# FireBoxTransfer

FireBoxTransfer is a free, open-source app that lets you explore, manage and transfer files between your PC and phone over your local network — no cloud, no accounts, no cables.

It is a fork of [LocalSend](https://localsend.org), an open-source cross-platform alternative to AirDrop, and remains protocol-compatible with it at this stage.

> [!NOTE]
> This project has not been published anywhere yet (no app store listings, no CI, no website). The badges, download links and translation infrastructure that a typical README would show here don't exist yet for FireBoxTransfer — see [Getting Started](#getting-started) to build from source instead.

- [About](#about)
- [How It Works](#how-it-works)
- [Dependency Hierarchy](#dependency-hierarchy)
- [Getting Started](#getting-started)
- [Setup](#setup)
- [Troubleshooting](#troubleshooting)
- [Building](#building)
  - [Android](#android)
  - [iOS](#ios)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)

## About

FireBoxTransfer is a cross-platform app that enables secure communication between devices using a REST API and HTTPS encryption. Unlike other messaging apps that rely on external servers, FireBoxTransfer doesn't require an internet connection or third-party servers, making it a fast and reliable solution for local communication.

**Compatibility**

| Platform | Minimum Version | Note                                                                                                                      |
|----------|-----------------|----------------------------------------------------------------------------------------------------------------------------|
| Android  | 5.0             | -                                                                                                                           |
| iOS      | 12.0            | -                                                                                                                           |
| macOS    | 11 Big Sur      | -                                                                                                                          |
| Windows  | 10              | -                                                                                                                          |
| Linux    | N.A.            | Deps: Gnome: `xdg-desktop-portal` and `xdg-desktop-portal-gtk`, KDE: `xdg-desktop-portal` and `xdg-desktop-portal-kde`      |

## Setup

In most cases, FireBoxTransfer should work out of the box. However, if you are having trouble sending or receiving files, you may need to configure your firewall to allow FireBoxTransfer to communicate over your local network.

| Traffic Type | Protocol | Port  | Action |
|--------------|----------|-------|--------|
| Incoming     | TCP, UDP | 53317 | Allow  |
| Outgoing     | TCP, UDP | Any   | Allow  |

Also make sure to disable AP isolation on your router. It should be usually disabled by default but some routers may have it enabled (especially guest networks).
See [troubleshooting](#troubleshooting) for more information.

**Portable Mode**

Create a file named `settings.json` located in the same directory as the executable.
This file can be empty.
The app will use this file to store settings instead of the default location.

**Start hidden**

To start the app hidden (only in tray), use the `--hidden` flag (example: `fireboxtransfer_app.exe --hidden`).

## How It Works

FireBoxTransfer uses a secure communication protocol that allows devices to communicate with each other using a REST API. All data is sent securely over HTTPS, and the TLS/SSL certificate is generated on the fly on each device, ensuring maximum security.

For more information on the underlying protocol, see the [LocalSend Protocol documentation](https://github.com/localsend/protocol) (FireBoxTransfer remains compatible with it at this stage; product-specific extensions are documented in [docs/DOCUMENTACION_TECNICA.md](docs/DOCUMENTACION_TECNICA.md)).

## Dependency Hierarchy

![Dependency hierarchy](support/docs/dependency-hierarchy.svg)

## Getting Started

To compile FireBoxTransfer from the source code, follow these steps:

1. Install Flutter [directly](https://flutter.dev) or using [fvm](https://fvm.app) (see [version required](.fvmrc))
2. Install [Rust](https://www.rust-lang.org/tools/install)
3. Clone this repository
4. Run `cd app` to enter the app directory
5. Run `fvm flutter pub get` to download dependencies
6. Run `fvm flutter run` to start the app

> [!NOTE]
> This project requires an older Flutter version (specified in [.fvmrc](.fvmrc)) and thus build issues may be caused by a mismatch between the required and the (system-wide) installed Flutter version.
> To make development more consistent, this project uses [fvm](https://fvm.app) to manage the project Flutter version — always run `fvm flutter` / `fvm dart` instead of the bare commands.

## Troubleshooting

| Issue              | Platform (Sending) | Platform (Receiving) | Solution                                                                                                                                |
|---------------------|--------------------|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| Device not visible | Any                | Any                   | Make sure to disable AP-Isolation on your router. If it is enabled, connections between devices are forbidden.                          |
| Device not visible | Any                | Windows                | Make sure to configure your network as a "private" network. Windows might be more restrictive when the network is configured as public. |
| Device not visible | macOS, iOS         | Any                   | You can try to toggle the "Local Network" permission under "Privacy" in the OS settings.                                                |
| Speed too slow      | Any                | Any                   | Use 5 Ghz; Disable encryption on both devices                                                                                            |

## Building

These commands are intended for maintainers only. Make sure to run them from the `app` directory, using `fvm flutter` instead of `flutter`.

### Android

Traditional APK

```bash
fvm flutter build apk
```

AppBundle for Google Play

```bash
fvm flutter build appbundle
```

### iOS

```bash
fvm flutter build ipa
```

### macOS

```bash
fvm flutter build macos
```

### Windows

**Traditional**

```bash
fvm flutter build windows
```

**Local MSIX App**

```bash
fvm flutter pub run msix:create
```

### Linux

**Traditional**

```bash
fvm flutter build linux
```

**AppImage**

```bash
appimage-builder --recipe AppImageBuilder.yml
```
