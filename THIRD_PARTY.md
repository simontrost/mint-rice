# Third-party components and asset provenance

This repository is a personal configuration snapshot built with upstream software.

| Component | Origin | License / remarks |
| --- | --- | --- |
| Cinnamon Island (modified) | https://github.com/rovillela-afk/cinnamon-island | GPL-3.0-or-later; original author credited; see `cinnamon/island/LICENSE`. Python engine not bundled. |
| Liquid-GRUB (modified) | https://github.com/Purp1eDuck2008/Liquid-GRUB | Repository includes GPL-3.0; see `grub/LICENSE`. Upstream theme images include icons attributed to icons8.com; verify icon licenses separately. |
| Blur Cinnamon | https://github.com/klangman/BlurCinnamon | Only exported settings, not the extension source. |
| Rounded Corners | https://cinnamon-spices.linuxmint.com/extensions/view/117 | Only exported settings. |
| Colloid Icons | https://github.com/vinceliuice/Colloid-icon-theme | Not bundled: install from upstream. |
| Now Clocking / Conky | https://github.com/simontrost/conky-rainmeter-mond | Check the upstream project and its embedded third-party files/fonts before redistributing. |
| Mintbook-Glass shell theme | Personal adaptations of existing Cinnamon theme assets | **Verify upstream base theme(s), artwork, and licenses** before publishing the full directory. |
| Space wallpapers (`space1.jpg`, `space2.jpg`, `space3.jpg`) | [DarkShadowShell](https://github.com/shadowww-dev/DarkShadowShell/tree/main/wallpapers) | Identical to upstream `space-black-hole.jpg`, `space-planet.jpg`, and `space-galaxy.jpg`, respectively (verified by Git blob SHA-1). Upstream repository carries the MIT license; copyright notice and license text copied to `assets/wallpapers/LICENSE.DarkShadowShell`. Any independent third-party rights in artwork are not separately established. |
| Other artwork | `cinnamon/themes/Mintbook-Glass/cinnamon/Wallpaper.png` and `grub/theme/background.png` | Provenance/redistribution rights still require verification, including any embedded icons or third-party artwork. |
| Fonts | Quicksand, Montserrat, Gotham and other fonts may be referenced | Font binaries are not bundled intentionally. Download them from authorized sources under their respective licenses. |

Source-repository licensing and attribution do not automatically establish rights to artwork sourced from outside those repositories. Verify the remaining theme artwork before redistribution. Respect original copyright notices in modified source files.
