Workshop Map Loader
===================
This is a SourceMod plugin for Counter-Strike: Global Offensive. Head over to the [Allied Modders Forum Thread](https://forums.alliedmods.net/showthread.php?p=2081908) for more information.

Description
-----------
This plugin searches for workshop maps in your servers map directory and assists the admin in handling those. It will also ensure that the current game mode will get automatically adjusted, if requested by the admin.

The plugin was developed for CS:GO and will not work in other games.

Features
--------
### Admin menu
The Top-Level menu is dynamically built depending on your servers' workshop maps and their community tags:

![Admin menu](http://www0.xup.in/exec/ximg.php?fid=19801421 "Admin menu")

Each category hosts the corresponding map:

![Category menu](http://www0.xup.in/exec/ximg.php?fid=12963802 "Category menu")

Note, that a map may appear in multiple categories depending of it's tags.

### Vote menu
It's possible to interact with the stock MapChooser plugin or the [MapChooser Extended](https://forums.alliedmods.net/showthread.php?t=156974) plugin.

![Vote menu](http://www0.xup.in/exec/ximg.php?fid=35241326 "Vote menu")

Commands
--------
* **sm_wml** brings up the map list (for Admins with at least changemap-Permissions)
* **sm_wml_reload** refreshes the map list (useful to be triggered by the admin after the server has downloaded new workshop maps)
* **sm_wml_rebuild** dumps the database content and rebuilds it from scratch
* **sm_wml_vote_now** requests an instant next map vote
sm_wml_nominate_random_maps will nominate a given amount of random maps from the database for the next vote. It's behavior is controlled by the `sm_wml_nominate_*` Cvars.

Snippet for your *adminmenu_custom.txt*:
```
	"ServerCommands"
	{
		"Load Workshop Map"
		{
			"cmd"		"sm_wml"
			"admin"		"sm_changemap"
		}
		"Refresh Workshop Map List"
		{
			"cmd"		"sm_wml_reload"
			"admin"		"sm_changemap"
		}
		"Start Next Workshop Map Vote"
		{
			"cmd"		"sm_wml_vote_now"
			"admin"		"sm_changemap"
		}
	}
```

Cvars
-----
This plugin generates it's config file in csgo/cfg/sourcemod/wml.cfg after first load.
* **sm_wml_version** returns current plugin version
* **sm_wml_changemode** will change the game mode corresponding to the selected category `<1 = Enabled/Default, 0 = Disabled>`
* **sm_wml_autoreload** defines if the database content should be refreshed on plugin reload. It's recommended to turn it off after the first successful load for performance reasons `<1 = Enabled/Default, 0 = Disabled>`
* **sm_wml_armsrace_weapon** defines the weapon in Armsrace mode where voting shall pop up if the first player acquired it `<awp = Default>`
* **sm_wml_nominate_all_maps** defines if all maps shall be allowed to get into vote nomination rather than only maps matching the current game mode (e.g. in Casual there won't be Armsrace maps nominated) `<1 = Enabled, 0 = Disabled/Default>`
* **sm_wml_override_mapcycle** creates and sets a custom mapcycle file on each mapchange with workshop maps matching the current game mode. This will allow excellent automated interaction with stock map management plugins `<1 = Enabled/Default, 0 = Disabled>`

Translations
------------
There currently exist the following translations:
* English
* German
* Russian
* Romanian

Plans and TODOs
---------------
Suggestions welcome!
* More translations
* Add map blacklist to exclude "broken" map IDs

Optional Dependencies
---------------------
* This plugin will be automatically updated by the [Updater](http://forums.alliedmods.net/showthread.php?t=169095) plugin
* Use [MapChooser Extended](https://forums.alliedmods.net/showthread.php?t=156974) if you like to utilize advanced voting
* You also might have a look at my [Server Hibernate Fix](https://github.com/nefarius/ServerHibernateFix) plugin to avoid locking up your server on hibernation

Installation/Requirements
-------------------------
1. You should have at least SourceMod v1.5.3
2. Your server must be running at least one of the following extensions:
 * cURL (recommended)
 * System2
3. Write-Permissions to `sourcemod/data` and  `sourcemod/data/sqlite` directory.
4. Download the [latest archive](https://github.com/nefarius/WorkshopMapLoader/archive/master.zip).
5. Extract the contents of `WorkshopMapLoader-master` into your servers `csgo/addons/sourcemod` directory.
6. Restart your server or load the plugin by hand.
7. Adjust the configuration file to your needs or just go with the defaults.
8. Leave feedback!
