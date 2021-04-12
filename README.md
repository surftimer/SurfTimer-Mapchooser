# SM Mapchooser SurfTimer Edit

## About

This is a edit of the default SourceMod mapchooser and nomination plugin, it provides functionality for Fluffys SurfTimer or it's forks to display tiers of maps in the nominate and vote menus.

## Requirements

* Sourcemod 1.8+
* MySQL 5.7 / 8+ / MariaDB supported
* [SurfTimer](https://github.com/surftimer/Surftimer-Official)
<br><sup>I mean it works with any fork as long as the layout of ck_maptier and ck_zones are the same as in [Fluffys](https://github.com/fluffyst/Surftimer) archived repo :wink:</sup>

**Compilation Requirements (Includes):**

* [Sourcemod](https://www.sourcemod.net/downloads.php?branch=stable)
* [Surftimer](https://github.com/surftimer/Surftimer-olokos/tree/master/addons/sourcemod/scripting/include)
* [AutoExecConfig](https://github.com/Impact123/AutoExecConfig)
* [ColorLib](https://github.com/c0rp3n/colorlib-sm)

## Installation

* Get latest plugin files from **[Release Page](https://github.com/qawery-just-sad/surftimer-mapchooser/releases)**
* Copy files over to `csgo/addons/sourcemod/plugins`
* Set `sm_server_tier` in `csgo/cfg/sourcemod/mapchooser.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0` and if you want all tiers `sm_server_tier 0`

<br><sup>This plugin is broken, trust me, it only works on my server 😝</sup>
