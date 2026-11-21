# CHUD (Compass HUD)

A compass bar for World of Warcraft Forever. It shows N/E/S/W letters, ticks and degrees across the top of the screen,
with themes, an XP fill built into the bar, fading hairline edges, and optional quest, rare, treasure and gathering markers.

## Install

Download CHUD-1.0.zip.

* Extract it into World of Warcraft\_forever_\Interface\AddOns\. The path should end in AddOns\CHUD\CHUD.toc. Windows’ “Extract All” often creates an extra nested folder, which breaks the addon, so check that CHUD.toc sits directly inside CHUD.
* Fully restart the game. The new addon probably doesn’t appear with /reload.
* On the character select screen, open AddOns and confirm CHUD is enabled.
* In game, type /chud for settings or right-click the bar for the quick menu.

## Use

- `/chud` opens settings. `/chud unlock`, `/chud lock`, `/chud center` and `/chud reset` do what they say.
- `/chud install` asks first, then resets every setting and the imported gathering data and runs the setup tour as on a first install: themes, what to show, gathering and rare data (the import happens there, only when you press the button), and fading. It also opens by itself the first time.
- Right-click the bar for the quick menu (markers, unlock, center).
- `/chud debug` collects diagnostic reports into one copyable window, useful when reporting a problem.

## Questie

If Questie is installed, CHUD uses its map icons for quest objectives, turn-ins and quest givers, and turns this on
automatically. The focused quest gets the largest icon, other icons shrink with distance, and clicking a quest icon on the
bar focuses that quest. Questie options are in the right-click menu. Without Questie, CHUD uses the game's own quest markers.

## Gathering and rare data

CHUD reads other addons you already have and never changes them.

- **GatherLite** (recommended) supplies herb, ore and chest positions. **GatherMate2** with GatherMate2_Data also works for herbs and ore. CHUD keeps its own imported copy, and having both on is not needed, so you may want to turn GatherMate2 off.
- **RareScanner** supplies rare NPC spawn points. CHUD reads its installed files each time you play, so it follows RareScanner's updates. Restart the game once after installing it.
- The Next Node pointer leads you to the nearest unvisited node, and Highlight Node lights up the real object when you arrive. It adjusts a few game targeting settings and gives them back when switched off.

## Status

Beta. The marker features depend on map and quest APIs that have not been fully tested on Forever. I was able to get some things partially working but I need feedback going forward.

## License

MIT, see `LICENSE`.
