# Vendored: libghostty-vt

`ghostty-vt.xcframework` is the prebuilt **libghostty-vt 1.0.0** release (the terminal core from Ghostty, MIT licensed),
unmodified except that the macOS slice was dropped — this app is iOS only.

- Source: <https://release.files.ghostty.org/libghostty-vt/1.0.0/ghostty-vt-1.0.0.xcframework.zip>
- SHA256 of that zip: `2c32b7409b2b6c2ef6cfd606526de357762ad458bdc27134ad074e86506a8bc2`
- Slices kept: `ios-arm64`, `ios-arm64-simulator` (arm64 only — the project excludes `x86_64` for the simulator)
- Module name: `GhosttyVt`, umbrella header `ghostty/vt.h`
- Licence: MIT, © Mitchell Hashimoto and Ghostty contributors — see <https://github.com/ghostty-org/ghostty/blob/main/LICENSE>

It is a static library (`embed: false` in `project.yml`), so only the objects the app references are linked in.

To refresh it:

```sh
curl -LO https://release.files.ghostty.org/libghostty-vt/1.0.0/ghostty-vt-1.0.0.xcframework.zip
shasum -a 256 ghostty-vt-1.0.0.xcframework.zip   # must match the hash above
unzip -q ghostty-vt-1.0.0.xcframework.zip -d /tmp/ghosttyvt
# keep only the two iOS slices (edit AvailableLibraries in the xcframework's Info.plist), then
rsync -a --delete /tmp/ghosttyvt/ghostty-vt-1.0.0.xcframework/ Vendor/ghostty-vt.xcframework/
```
