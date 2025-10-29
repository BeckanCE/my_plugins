public Plugin myinfo =
{
	name = "Spawn fijado de Tank",
	author = "Beckham CE",
	description = "Establece el spawn del tank en 85% en el primer mapa de Big Wat.",
	version = "1.0",
	url = ""
};

public OnMapStart()
{
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    
    if (StrEqual(mapName, "bwm1_climb"))
    {
        CreateTimer(22.0, Timer_ExecuteCommand, _, TIMER_FLAG_NO_MAPCHANGE);
        
        CreateTimer(25.0, Timer_ChangeCvar, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action:Timer_ExecuteCommand(Handle:timer, any:unused)
{
    ServerCommand("sm_ftank 85");
    
    return Plugin_Handled;
}

public Action:Timer_ChangeCvar(Handle:timer, any:unused)
{
    SetConVarInt(FindConVar("l4d_boss_vote"), 0);
    
    return Plugin_Handled;
}
