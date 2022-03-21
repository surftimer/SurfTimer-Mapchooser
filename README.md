# SurfTimer - Map Chooser, Nominations, and RTV

## Introduction

This is an edit of the default SourceMod mapchooser, nominations, and rtv plugins. It provides functionality for SurfTimer or its forks to display relevant information and provide further functionality in the map voting and nomination processes.

**This is a fork that is being tweaked to suit my personal needs for my servers, such as whitelisting maps using the mapcycle.txt file. Feel free to use it, and feel free to report things that may be broken, but just note that I may not always be available to fix everything!** Pull requests are encouraged, feel absolutely free to contribute. 😄

## List of Things I've Added

* These plugins will only list maps specified in `mapcycle.txt`. In contrast to its parent repositories, which do not refer to `mapcycle.txt`, this allows us to have further control over what maps you want hosted instead of having every single map in the `ck_maptier` database table listed automatically.
* Added an option to `/nominate` that allows players to nominate a map from a list of maps that they have not completed. Works for styles too!

## Requirements

* Sourcemod 1.8+
* MySQL 5.7 / 8+ / MariaDB supported
* [SurfTimer](https://github.com/surftimer/Surftimer-Official)

**Compilation Requirements (Includes):**

* [Sourcemod](https://www.sourcemod.net/downloads.php?branch=stable)
* [Surftimer](https://github.com/surftimer/Surftimer-Official/tree/master/addons/sourcemod/scripting/include)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* [ColorLib](https://github.com/c0rp3n/colorlib-sm)

## Installation

* Download the [latest release](https://github.com/1zc/Surftimer-Mapchooser/releases). (It will be a ZIP file named after the release version)
* Extract the release ZIP file to your server's `csgo` folder, and start your server to generate the required config files.
* Set `sm_server_tier` in `csgo/cfg/sourcemod/st-mapchooser.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0` and if you want all tiers `sm_server_tier 0`
* Make sure the maps you want available on the server are listed in `csgo/mapcycle.txt`!
