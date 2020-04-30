# SM Mapchooser SurfTimer Edit

## About

This is a edit of the default SourceMod mapchooser and nomination plugin, it provides functionality for any ckSurf based timer to display tiers of maps in the nominate and vote menus 

## Requirements

* Sourcemod 1.8
* MySQL

## Installation

* Upload all the files to your csgo server directory
* Add a MySQL database called `surftimer` to `csgo/addons/sourcemod/configs/databases.cfg` (Note: must match the database you're using for SurfTimer`)
* Set `sm_cksurf_type` in `cfg/nominations.cfg` (0 if using original/nikos/marcos ckSurf, 1 if using fluffys/z4lab's SurfTimer)
* Set `sm_server_tier` in `cfg/nominations.cfg` to the tier of maps you want appearing the nominate list. Example, for a tier 1-3 server, set it to `sm_server_tier 1.3`, a tier 1 only server would be `sm_server_tier 1.0`
