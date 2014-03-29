/* ================================================================================
 * INTERNAL GAMEMODE HELPERS
 * ================================================================================
 */

// GS:GO Game Types
enum
{
	GameType_Classic		= 0,
	GameType_GunGame		= 1,
	GameType_Training		= 2,
	GameType_Custom			= 3,
}
// GS:GO Classic Types
enum
{
	ClassicMode_Casual		= 0,
	ClassicMode_Competitive	= 1,
}
// GS:GO Arsenal Modes
enum
{
	GunGameMode_ArmsRace	= 0,
	GunGameMode_Demolition	= 1,
	GunGameMode_DeathMatch	= 2,
}

// CS:GO Next Map Mode
enum
{
	NextMapMode_Casual		= 0,
	NextMapMode_Competitive	= 4,
	NextMapMode_Armsrace	= 3,
	NextMapMode_Demolition	= 2,
	NextMapMode_Deathmatch	= 1,
	NextMapMode_Custom		= 5,
}
 
 
/*
 * Get current game mode/type.
 */
stock GetMode()
{
	new type = GetConVarInt(g_cvarGameType);
	new mode = GetConVarInt(g_cvarGameMode);
	
	if (type == GameType_Classic && mode == ClassicMode_Casual)
		return NextMapMode_Casual;
	if (type == GameType_Classic && mode == ClassicMode_Competitive)
		return NextMapMode_Competitive;
	if (type == GameType_GunGame && mode == GunGameMode_ArmsRace)
		return NextMapMode_Armsrace;
	if (type == GameType_GunGame && mode == GunGameMode_Demolition)
		return NextMapMode_Demolition;
	if (type == GameType_GunGame && mode == GunGameMode_DeathMatch)
		return NextMapMode_Deathmatch;
	if (type == GameType_Custom)
		return NextMapMode_Custom;
		
	return -1;
}

/*
 * Changes game type and game mode to set value
 */
stock ChangeMode(mode)
{
	// NOTE: this avoids possible loops
	g_IsChangingMode = true;
	switch (mode)
	{
		case NextMapMode_Casual:
			ChangeModeCasual();
		case NextMapMode_Competitive:
			ChangeModeCompetitive();
		case NextMapMode_Armsrace:
			ChangeModeArmsrace();
		case NextMapMode_Demolition:
			ChangeModeDemolition();
		case NextMapMode_Deathmatch:
			ChangeModeDeathmatch();
		case NextMapMode_Custom:
			ChangeModeCustom();
	}
	g_IsChangingMode = false;
}

// https://forums.alliedmods.net/showthread.php?p=1891305
stock ChangeModeCasual()
{
	SetConVarInt(g_cvarGameType, GameType_Classic);
	SetConVarInt(g_cvarGameMode, ClassicMode_Casual);
}

stock ChangeModeCompetitive()
{
	SetConVarInt(g_cvarGameType, GameType_Classic);
	SetConVarInt(g_cvarGameMode, ClassicMode_Competitive);
}

stock ChangeModeArmsrace()
{
	SetConVarInt(g_cvarGameType, GameType_GunGame);
	SetConVarInt(g_cvarGameMode, GunGameMode_ArmsRace);
}

stock ChangeModeDemolition()
{
	SetConVarInt(g_cvarGameType, GameType_GunGame);
	SetConVarInt(g_cvarGameMode, GunGameMode_Demolition);
}

stock ChangeModeDeathmatch()
{
	SetConVarInt(g_cvarGameType, GameType_GunGame);
	SetConVarInt(g_cvarGameMode, GunGameMode_DeathMatch);
}

stock ChangeModeCustom()
{
	SetConVarInt(g_cvarGameType, GameType_Custom);
	SetConVarInt(g_cvarGameMode, ClassicMode_Casual);
}
