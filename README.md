# Xcode Select Switcher

A [swiftDialog](https://github.com/swiftDialog/swiftDialog) front end for `xcode-select`. It lists every installed Xcode and the Command Line Tools, and switches the active developer directory.

## Requirements
- swiftDialog installed at `/usr/local/bin/dialog`
- Admin rights, or running as root (e.g. from Self Service)

## Usage
```bash
./xcode-select-switcher.sh
```

- **Switch** runs `xcode-select -s` on the selected install. Tick **Run first launch tasks** to also run `xcodebuild -runFirstLaunch` (Xcode only).
- **Reset to Default** runs `xcode-select --reset`.
- **Cancel** changes nothing.

Run as a normal user, it asks for an admin password. Run as root, it switches directly and shows the dialog to the logged-in user.

Installs are found in `/Applications/Xcode*.app`, through Spotlight (bundle ID `com.apple.dt.Xcode`, Trash excluded), and at `/Library/Developer/CommandLineTools`.

Switches are logged to the system log under `xcode-select-switcher`.
