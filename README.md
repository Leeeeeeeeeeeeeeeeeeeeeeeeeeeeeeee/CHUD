# CHUD (Compass HUD)

A compass bar for World of Warcraft Forever. It shows N/E/S/W letters, ticks and degrees across the top of the screen,
with themes, an XP fill built into the bar, fading hairline edges, and optional quest, rare, treasure and gathering markers.

## Install

Download CHUD-0.3.0.zip.

* Extract it into World of Warcraft\_forever_\Interface\AddOns\. The path should end in AddOns\CHUD\CHUD.toc. Windows’ “Extract All” often creates an extra nested folder, which breaks the addon, so check that CHUD.toc sits directly inside CHUD.
* Fully restart the game. The new addon probably doesn’t appear with /reload.
* On the character select screen, open AddOns and confirm CHUD is enabled.
* In game, type /chud for settings or right-click the bar for the quick menu.

## Use

- `/chud` opens settings.
- Right-click the bar for the quick menu (markers, unlock, center).

## Status

Beta. The marker features depend on map and quest APIs that have not been fully tested on Forever. I was able to get some things partially working but I need feedback going forward.

## License

MIT, see `LICENSE`.
