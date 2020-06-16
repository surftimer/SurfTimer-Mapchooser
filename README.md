# SM Mapchooser SurfTimer Edit

## About

This is a edit of the default SourceMod mapchooser and nomination plugin, it provides functionality for Fluffys SurfTimer or it's forks to display tiers of maps in the nominate and vote menus.

## Requirements

* Sourcemod 1.8+
* MySQL 5.7 / 8+ / MariaDB supported
* SurfTimer from [Olokos](https://github.com/surftimer/Surftimer-olokos) or [Fluffys](https://github.com/fluffyst/Surftimer)(NO LONGER MAINTAINED!)

## Installation

* Get latest plugin files from [Release Page](https://github.com/qawery-just-sad/surftimer-mapchooser/releases)
* Copy files over to `csgo/addons/sourcemod`
* Make sure that `csgo/addons/sourcemod/configs/databases.cfg` points to the surftimer database (You have to use the same database as the SurfTimer)
```
"surftimer"
	{
		"driver"			"mysql"
		"host"				"localhost"         // The ip address to the database server
		"database"			"surftimerdb"       // The database name that surftimer uses
		"user"				"dbuser"            // The user name that has access to that database
		"pass"				"dbuserpassword"    // The password for user specified above
		"port"              "3306"              // The port to the database server
	}
```
* Set `sm_server_tier` in `csgo/cfg/mapchooser.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0`
