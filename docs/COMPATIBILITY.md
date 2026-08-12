# Compatibility matrix

`tk` requires macOS 14 or newer on Apple silicon. Before each release, exercise the real installed DMG across the supported operating systems, representative hardware and input devices, and target applications. Link each matrix cell to a completed record using the template below rather than relying on memory or an unrecorded spot check.

## Release matrix

| macOS | Hardware | Memory | Input device | Target app | Dictation | Read selection | Offline | Record |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| 14.x latest | Apple silicon | 16 GB | Built-in microphone | TextEdit | Not run | Not run | Not run | |
| 14.x latest | Apple silicon | 16 GB | USB or Bluetooth microphone | Safari | Not run | Not run | Not run | |
| 15.x latest | Apple silicon | 24 GB or more | Built-in microphone | Notes | Not run | Not run | Not run | |
| 15.x latest | Apple silicon | 24 GB or more | USB or Bluetooth microphone | Mail | Not run | Not run | Not run | |
| 26.x latest | Apple silicon | 24 GB or more | Built-in microphone | Safari | Not run | Not run | Not run | |
| 26.x latest | Apple silicon | 24 GB or more | USB or Bluetooth microphone | Microsoft Word or equivalent third-party editor | Not run | Not run | Not run | |

### Required physical continuity gate

Before release, add linked records for built-in, USB, and Bluetooth microphones covering sleep/wake during recording and recognition, active-device disconnect, non-active-device connect, wake reprobe, and confirmation that tk never switches the microphone within an active transaction. Record warning and critical thermal or memory pressure separately when the test environment can produce them. Use `Blocked` when pressure cannot be induced safely. Do not convert software-test results into a physical-device `Pass`.

Use `Pass`, `Fail`, `Blocked`, or `Not run` for results. Add rows for macOS versions still receiving support, each materially different Mac class available to testers, and any application named in release notes or bug reports. At minimum, cover one standard AppKit editor, one browser text control, one Apple productivity app, and one third-party editor.

## Compatibility record template

Copy this section for each matrix row and store it in the release issue or test report.

### `<tag> / <macOS> / <device> / <target app>`

- Date and tester:
- Release tag:
- DMG SHA256 verified: yes / no
- Mac model and chip:
- Memory:
- macOS version and build:
- Input device, connection, and sample rate if known:
- Target app and version:
- Fresh install or upgrade:
- Accessibility granted: yes / no
- Microphone granted: yes / no
- Network state: online / offline
- Dictation result: Pass / Fail / Blocked
- Read-selection result: Pass / Fail / Blocked
- Clipboard restoration result: Pass / Fail / Blocked
- History and relaunch result: Pass / Fail / Blocked
- Observed latency or resource concern:
- Sleep/wake recording result: Pass / Fail / Blocked / Not run
- Sleep/wake recognition result and preserved-audio evidence:
- Active-device disconnect result and cleanup evidence:
- No-mid-transaction-switch result:
- Wake device-reprobe and new-operation result:
- Resource degraded / resourceBlocked result:
- Selected Speech profile unchanged: yes / no / Not run
- Evidence links:
- Issue links:
- Notes and exact reproduction steps:

## Known limitations and decisions

Record release-specific exceptions here with an issue link, affected matrix rows, severity, workaround, and the release owner's explicit ship/hold decision. Do not replace a failed matrix result with a prose exception.
