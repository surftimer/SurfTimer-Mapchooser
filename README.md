# SM Mapchooser SurfTimer Edit

## About

This is an edit of the default SourceMod mapchooser and nomination plugin, it provides functionality for Fluffys SurfTimer or it's forks to display extra information of maps in the nominate and voting menus.

**This is a fork that's being tweaked to suit my personal needs for my servers, such as whitelisting maps using the mapcycle.txt file. Feel free to use it, but just remember this is mostly suited for me!**

## Requirements

* Sourcemod 1.8+
* MySQL 5.7 / 8+ / MariaDB supported
* [SurfTimer](https://github.com/surftimer/Surftimer-Official)

**Compilation Requirements (Includes):**

* [Sourcemod](https://www.sourcemod.net/downloads.php?branch=stable)
* [Surftimer](https://github.com/surftimer/Surftimer-olokos/tree/master/addons/sourcemod/scripting/include)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* [ColorLib](https://github.com/c0rp3n/colorlib-sm)

## Installation

* Clone this repository and compile the script files located in `addons/sourcemod/scripting`.
* Copy files over to your server's `csgo/addons/sourcemod/plugins`
* Set `sm_server_tier` in `csgo/cfg/sourcemod/mapchooser.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0` and if you want all tiers `sm_server_tier 0`
* Make sure the maps you want available on the server are listed in `csgo/mapcycle.txt`.