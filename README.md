# SurfTimer - Map Chooser, Nominations, and RTV

## Introduction

This is an edit of the default SourceMod mapchooser, nominations, and rtv plugins. It provides functionality for SurfTimer or its forks to display relevant information and provide further functionality in the map voting and nomination processes.

Pull requests, issues, and suggestions are encouraged - feel absolutely free to contribute! 😄

## Previews:

Preview of Nomination Menu:

![Preview of Nomination Menu](https://i.rebooti.ng/f/zjybx.png)

## Requirements

* [SurfTimer](https://github.com/surftimer/Surftimer-Official)
* Sourcemod 1.11 (Please use the latest stable version!)
* A MySQL Database (Supported: MySQL 5.7, MySQL 8+, MariaDB)

**Compilation Requirements (Includes):**

* [SurfTimer](https://github.com/surftimer/Surftimer-Official/tree/master/addons/sourcemod/scripting/include)
* [Sourcemod 1.11](https://www.sourcemod.net/downloads.php?branch=stable)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* [ColorLib](https://github.com/c0rp3n/colorlib-sm)

## Installation

* Please make sure any other Map Chooser, Nominations, and RTV plugins are disabled!
* Download the [latest release](https://github.com/1zc/Surftimer-Mapchooser/releases). (It will be a ZIP file named after the release version)
* Extract the release ZIP file to your server's `csgo` folder, and start your server to generate the required config files.
* Set `sm_server_tier` in `csgo/cfg/sourcemod/st-mapchooser.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0` and if you want all tiers `sm_server_tier 0`
* Make sure the maps you want available on the server are listed in `csgo/mapcycle.txt`!
