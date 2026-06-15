<div align="center">
  <img src="https://github.com/user-attachments/assets/871b4942-a21e-440a-bf86-ff52b54897f3" width="96" height="96" style="border-radius: 1.25rem">
</div>
<div align="center" style="font-size: 2rem"><b>Swing Music iOS Client</b></div>

<div align="center"><b><sub><code>v1.0.0 (Beta 1)</code></sub></b></div>

<div align="center" style="padding-top: 1rem">

[![Download on TestFlight](https://img.shields.io/badge/Download_on-TestFlight-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://testflight.apple.com/join/68bWKBss)

</div>

**<div align="center" style="padding-top: 0.5rem"><a href="https://github.com/sponsors/swingmx" target="_blank">Sponsor Us ❤️</a> • [Swing Music Docs](https://swingmx.com/guide/introduction.html) • [r/SwingMusicApp](https://www.reddit.com/r/SwingMusicApp)</div>**

##

![Image](https://github.com/user-attachments/assets/208abfcd-0c3f-401d-817f-0b67e5c44339)
This client application allows you to stream music on your iPhone from your Swing Music server.

### Features

Below is a list of the currently implemented features:

- Albums, Artists and Playlists view
- Playback with a full-screen now playing
- Synced lyrics
- Search Tracks, Albums, Artists
- Queue management
- Equalizer and sleep timer
- Offline downloads
- Home Screen widget

More features will be implemented in the future.

### How to use

Join the beta on [TestFlight](https://testflight.apple.com/join/68bWKBss) and install the app. When you launch it, you should be prompted to scan a QR code or enter your server details manually.

You can go to `Settings > Pair device` on the webclient to get the QR code.

### Building

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonyz/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open SwingMusicApp.xcodeproj
```

### License

This software is provided to you with terms stated in the AGPLv3 License. Read the full text in the `LICENSE` file located at the root of this repository.
