# BeamNG Missions

A mod for [BeamNG.drive](https://www.beamng.com/) that adds GTA-style missions to the map. Drive into glowing beacon columns scattered around the map to start missions — chase down fleeing targets, escape police pursuits, tail suspects, survive endless waves, or race to a destination under fire.

## Features

- **Glowing mission markers** placed at key locations on the map
- **ImGui HUD panel** (top-left) showing every mission with compass direction and distance
- **Five mission types:**

| Type | Description |
|------|-------------|
| **Chase** | A target vehicle spawns and flees — catch and destroy it |
| **Escape** | Police cars spawn around you — outrun them all before time runs out |
| **Follow** | Tail a moving target, stay close without damaging it |
| **Endure** | Police recycle endlessly — survive the full time limit |
| **Reach** | Escape recycling police and drive to a destination column of light |

## Requirements

- [BeamNG.drive](https://www.beamng.com/) (tested on the current release)
- West Coast USA map (included with the base game)

## Installation

1. Download the latest release from the [Releases](https://github.com/Allenjonesing/BeamNG-Missions/releases) page and unzip it, you can define the extraction path in Windows to skip step 2.
   ```
   C:\Users\<YourUsername>\AppData\Local\BeamNG\BeamNG.drive\<version>\mods\unpacked
   ```
2. If needed, Open the unzipped `BeamNG-Missions-<version>` folder and move the internal `BeamNG-Missions-<version>` folder as-is into the BeamNG unpacked mods directory:
   ```
   C:\Users\<YourUsername>\AppData\Local\BeamNG\BeamNG.drive\<version>\mods\unpacked
   ```
   For example, mod contents should look like this after install:
   ```
   C:\Users\YourUsername\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\BeamNG-Missions-v0.2\README.md
   ```
4. Launch BeamNG.drive and load the **West Coast USA** map. Works on other maps but Mission placement may be off.
5. Set your vehicle's License plate to the '.Jonesing Missions Mod'.
6. The mission markers will appear automatically — look for the glowing columns of light and check the HUD panel in the top-left corner for directions to each mission.

> **Tip:** If the `mods\unpacked` directory does not exist, create it manually.

## How It Works

The mod hooks into BeamNG via a dummy jbeam part that occupies a license-plate slot. When the game loads the part, it triggers a Lua controller that loads the mission manager extension into the Game Engine. The extension then places mission markers, manages AI vehicles, and runs the HUD.

## License

This source code is provided under the terms of the [bCDDL v1.1](http://beamng.com/bCDDL-1.1.txt).
