# Prototype understandable Speech profile settings

Type: prototype
Status: resolved
Blocked by: 03, 04
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

What is the smallest accessible Settings presentation that lets a non-technical user compare Dictation quality and Reading quality, notice practical profile limits, explicitly download or remove optional profiles, understand progress and failures, and still reach technical details when wanted?

## Prototype under review

[Open the three-variant Speech profiles Settings prototype](../../../Sources/TK/Views/SettingsProfilesPrototype.html). Use the floating arrows or Left/Right keys to switch layouts, and the State menu to inspect ready, downloading, failed, and low-storage presentations.

## Answer

Use **Variant C — Focused sidebar** inside tk's existing Settings window. This is a new Settings destination, not a new window or standalone surface.

The Settings sidebar gives Speech profiles its own destination alongside the existing settings categories. Within it:

- Present Dictation quality first and Reading quality second.
- Use a vertical, radio-style list so names, “Best for” guidance, exact storage, and relative memory can be compared without opening another view.
- Mark the current defaults as both Selected and Recommended.
- Keep Download and Remove as explicit actions on the relevant profile row. Installing does not select a profile.
- Show download progress and Cancel inline with the affected profile group.
- Show failures and insufficient-storage explanations inline, in text as well as color, while stating that the selected profile did not change.
- Put common practical limits in plain-language disclosures below each group. Put filenames, versions, checksums, and licenses in a separate Technical details disclosure.
- Keep the local-processing reassurance at the top: “Everything runs privately on this Mac.”

Use native macOS Settings navigation and controls in the production implementation so keyboard navigation, focus, VoiceOver semantics, contrast, and reduced-motion behavior come from SwiftUI rather than being recreated. The HTML artifact is only the reviewed layout reference.
