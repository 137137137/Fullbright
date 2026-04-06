# Fullbright

**Unlock the full XDR brightness potential of your MacBook Pro display**

<div align="center">

![macOS](https://img.shields.io/badge/macOS-13.0+-blue?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![XDR](https://img.shields.io/badge/XDR-Compatible-purple.svg)

*A lightweight menu bar app that enables true XDR brightness on supported MacBook Pro displays*

</div>

## Features

- **One-click XDR activation** - Toggle XDR mode directly from your menu bar
- **Smart detection** - Automatically detects XDR-compatible displays
- **100% Safe** - Uses Apple's official system libraries and built-in safety mechanisms
- **Lightweight** - Minimal system resources with native SwiftUI interface
- **Menu bar integration** - Clean, unobtrusive interface that stays out of your way

## Compatibility

Fullbright works with MacBook Pro models featuring XDR displays:
- MacBook Pro 14 M1 +
- MacBook Pro 16 M1 +

## Motivation

I was frustrated by the lack of a free, simple, native Swift app that accomplishes XDR brightness control. While paid solutions exist, there was no straightforward, open-source menu bar app that simply toggles XDR mode without unnecessary complexity.

## How It Works

Fullbright uses Apple's **SkyLight framework** to control display presets - the exact same method used by Lunar and BetterDisplay. This is the proper, Apple-sanctioned approach rather than overlay methods that use MetalKit to overlay CIImages with transparent colors in EDR color space over display windows while applying color blending filters.

This approach:

- Uses official Apple APIs for display control
- Leverages built-in safety mechanisms - Apple automatically dims pixels if they get too hot
- Follows the identical technical implementation as established professional tools
- Maintains display integrity through hardware-level protections
- Avoids complex overlay techniques that can impact system performance

## Installation

### Option 1: Download Release
1. Download the latest release from the [Releases](../../releases) page
2. Move `Fullbright.app` to your Applications folder
3. Launch and grant necessary permissions when prompted

### Option 2: Build from Source
```bash
git clone https://github.com/137137137/Fullbright.git
cd Fullbright
open Fullbright.xcodeproj
```
Build and run in Xcode (requires macOS 13.0+ and Xcode 14+)

## Usage

1. **Launch Fullbright** - The app will appear in your menu bar
2. **Check compatibility** - If XDR is supported, you'll see the toggle option
3. **Enable XDR** - Click the toggle to activate enhanced brightness
4. **Enjoy** - Your display now operates at its full XDR brightness potential

## Safety & Technical Details

### Why Fullbright is Safe

- **Hardware Protection**: MacBook Pro displays have built-in thermal management that automatically reduces pixel brightness when temperatures get too high
- **Apple's Safety Mechanisms**: The SkyLight framework includes Apple's own safeguards for display management
- **Proven Approach**: Uses the exact same underlying technology as Lunar and BetterDisplay
- **No Hardware Modification**: Works entirely through software, making no permanent changes to your system

### Technical Implementation

Fullbright utilizes Apple's private SkyLight framework to:
1. Detect available display presets
2. Identify XDR-capable presets (those supporting 1600+ nits)
3. Switch between standard and XDR brightness modes
4. Maintain preset state across app launches


## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

Fullbright is not affiliated with Apple Inc. This software uses documented system frameworks and follows established patterns for display management. Use at your own discretion.

## Technical Credits

- Built with Apple's SwiftUI framework
- Uses Apple's SkyLight framework for display control
- Implements the same display preset switching method as Lunar and BetterDisplay

---

<div align="center">

**A free, native Swift solution for XDR brightness control**

[Report Bug](../../issues) · [Request Feature](../../issues) · [Star this repo](../../stargazers)

</div>