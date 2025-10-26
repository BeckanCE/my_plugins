#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

enum struct CPlayerCrownData
{
	char m_sName[64];
	int m_iCrowns;
	int m_iPosition;
}

#define TOP_NUMBER 5

ConVar hEnablePlugin, hCvarAnnounce, g_hCvarMPGameMode,
	g_hCvarModesTog, g_hCvarSurvivorRequired, g_hCvarAISurvivor, g_hCvar1v1Separate;
bool g_bCvarAllow;
ConVar g_hCvarSurvivorLimit, g_hCvarInfectedLimit;
bool g_bRoundEndAnnounce;
char datafilepath[256];
char datafilepath_1v1[256];
int timerDeath[MAXPLAYERS+1];
int Crowns[MAXPLAYERS+1];
int Kills[MAXPLAYERS+1];
int CvarAnnounce;
bool Is1v1;

KeyValues g_hData;

public Plugin myinfo =
{
	name = "Top Witch Crowners",
	description = "Anuncia los crowns a la Witch y los guarda en data/crown_database.txt",
	author = "Beckham CE (Base: thrillkill, JNC, Harry)",
	version = "2.5-Crowns",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	EngineVersion test = GetEngineVersion();
	
	if( test != Engine_Left4Dead2 && test != Engine_Left4Dead)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	
	return APLRes_Success; 
}

public void OnPluginStart()
{
	hEnablePlugin 			= CreateConVar("crown_database_enable", 			"1", "¿Activar este plugin?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hCvarAnnounce 			= CreateConVar("crown_database_announce", 			"3", "Controla qué mensajes se anuncian. Suma los números: 1=Crown exitoso, 2=Crown fallido (solo al jugador), 4=Stats de fin de ronda, 8=Nuevo total al jugador.", FCVAR_NOTIFY, true, 0.0, true, 15.0);
	g_hCvarModesTog 		= CreateConVar("crown_database_modes_tog",			"0", "Activar el plugin en estos modos de juego. 0=Todos, 1=Coop, 2=Survival, 4=Versus. Sumar números.", FCVAR_NOTIFY, true, 0.0, true, 7.0);
	g_hCvarSurvivorRequired = CreateConVar("top_crown_survivors_required",		"2", "Número de Supervivientes requeridos como mínimo para activar este plugin", FCVAR_NOTIFY , true, 1.0, true, 32.0);
	g_hCvarAISurvivor 		= CreateConVar("crown_database_ai_survivor_enable",	"1", "¿Contar crowns de Supervivientes IA? [1: Sí, 0: No]", FCVAR_NOTIFY , true, 0.0, true, 1.0);
	g_hCvar1v1Separate 		= CreateConVar("crown_database_1v1_seprate",		"0", "Guardar la base de datos de crowns 1v1 en modo 1v1.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	GetCvars();
	hCvarAnnounce.AddChangeHook(ConVarChange_hCvarAnnounce);
	
	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarSurvivorLimit = FindConVar("survivor_limit");
	g_hCvarInfectedLimit = FindConVar("z_max_player_zombies");
	hEnablePlugin.AddChangeHook(ConVarChanged_Allow);
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarSurvivorRequired.AddChangeHook(ConVarChanged_Allow);
	g_hCvarSurvivorLimit.AddChangeHook(ConVarChanged_Allow);

	BuildPath(Path_SM, datafilepath, 256, "data/%s", "crown_database.txt");
	BuildPath(Path_SM, datafilepath_1v1, 256, "data/%s", "1v1_crown_database.txt");
	RegConsoleCmd("sm_crowns", Command_Stats, "Muestra tus estadísticas de crowns y tu rango.", 0);
	RegConsoleCmd("sm_topcrowns", Command_Top, "Muestra el TOP 5 de jugadores con más crowns.", 0);

	AutoExecConfig(true,"l4d2_crown_database");
}

public void OnPluginEnd()
{
	delete g_hData;
}

public void OnConfigsExecuted()
{
	IsAllowed();

	int SurvivorsLimit = g_hCvarSurvivorLimit.IntValue;
	int InfectedLimit = g_hCvarInfectedLimit.IntValue;
	if(SurvivorsLimit == 1 && InfectedLimit == 1)
	{
		Is1v1 = true;
	}
	else
	{
		Is1v1 = false;
	}

	delete g_hData;
	g_hData = new KeyValues("crowndata");
	if(g_hCvar1v1Separate.BoolValue && Is1v1)
	{
		if (!g_hData.ImportFromFile(datafilepath_1v1))
		{
			g_hData.JumpToKey("data", true);
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			g_hData.SetNum("count", 0);
			g_hData.Rewind();
			g_hData.ExportToFile(datafilepath_1v1);
		}
	}
	else
	{	
		if (!g_hData.ImportFromFile(datafilepath))
		{
			g_hData.JumpToKey("data", true);
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			g_hData.SetNum("count", 0);
			g_hData.Rewind();
			g_hData.ExportToFile(datafilepath);
		}
	}
}

void IsAllowed()
{
	bool bCvarAllow = hEnablePlugin.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	int SurvivorsLimit = g_hCvarSurvivorLimit.IntValue;
	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true && SurvivorsLimit>= g_hCvarSurvivorRequired.IntValue)
	{
		g_bCvarAllow = true;
		GetCvars();
		HookEvent("witch_killed", Event_Witch_Killed);
		HookEvent("player_death", Event_PlayerDeath);
		HookEvent("round_start", Event_RoundStart);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("player_bot_replace", Event_Replace);
		HookEvent("bot_player_replace", Event_Replace);
	}
	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false || SurvivorsLimit < g_hCvarSurvivorRequired.IntValue) )
	{
		g_bCvarAllow = false;
		UnhookEvent("witch_killed", Event_Witch_Killed);
		UnhookEvent("player_death", Event_PlayerDeath);
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("player_bot_replace", Event_Replace);
		UnhookEvent("bot_player_replace", Event_Replace);
	}
}

bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == INVALID_HANDLE )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog == 0) return true;

	char CurrentGameMode[32];
	g_hCvarMPGameMode.GetString(CurrentGameMode, sizeof(CurrentGameMode));
	int g_iCurrentMode = 0;
	if(StrEqual(CurrentGameMode,"coop", false))
	{
		g_iCurrentMode = 1;
	}
	else if (StrEqual(CurrentGameMode,"versus", false))
	{
		g_iCurrentMode = 4;
	}
	else if (StrEqual(CurrentGameMode,"survival", false))
	{
		g_iCurrentMode = 2;
	}

	if( g_iCurrentMode == 0 )
		return false;
		
	if(!(iCvarModesTog & g_iCurrentMode))
		return false;

	return true;
}

void ConVarChanged_Allow(ConVar convar, const char[] oldValue, const char[] newValue)
{	
	IsAllowed();
}

void ConVarChange_hCvarAnnounce(ConVar convar, const char[] oldValue, const char[] newValue)
{	
	GetCvars();
}

void GetCvars()
{
	CvarAnnounce = hCvarAnnounce.IntValue;
}

public void OnMapStart()
{
	PrecacheSound("player/orch_hit_Csharp_short.wav", true);
	ClearStatsCounter();
}

public void OnMapEnd()
{
	delete g_hData;
}

Action Command_Stats(int client, int args)
{
	if(client == 0) return Plugin_Handled;
	if(!g_bCvarAllow) return Plugin_Handled;

	ShowCrownRank(client);
	PrintCrownsToClient(client);

	return Plugin_Handled;
}

Action Command_Top(int client, int args)
{
	if(client == 0) return Plugin_Handled;
	if(!g_bCvarAllow) return Plugin_Handled;
	
	PrintTopCrowners(client);

	return Plugin_Handled;
}

void Event_Replace(Event event, const char[] name, bool dontBroadcast) 
{
	int player = GetClientOfUserId(event.GetInt("player"));
	int bot = GetClientOfUserId(event.GetInt("bot"));
	Crowns[player] = 0;
	Crowns[bot] = 0;
	Kills[player] = 0;
	Kills[bot] = 0;
}

public void Event_Witch_Killed(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client || !IsClientInGame(client) || GetClientTeam(client) != 2)
	{
		return;
	}
	
	if (IsFakeClient(client) && !g_hCvarAISurvivor.BoolValue)
	{
		return;
	}

	Kills[client]++;

	if (GetEventBool(event, "oneshot"))
	{
		Crowns[client]++;
		Crowned(client);
		CreateTimer(0.0, Timer_Statistic, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(0.1, Timer_PrintTopCrowns, 0, TIMER_FLAG_NO_MAPCHANGE);

		if (CvarAnnounce & 1)
		{
			CPrintToChatAll("[{green}Top Crowners{default}] {olive}%N {default}realizo un {green}crown {default}a la {lightgreen}Witch%s", client, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : "!");
		}
	}
	else
	{
		if ((CvarAnnounce & 2) && !IsFakeClient(client))
		{
			CPrintToChat(client, "[{green}Top Crowners{default}] Mataste a la {lightgreen}Witch{default}, ¡pero no fue un {green}crown!");
		}
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) 
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim || !IsClientInGame(victim) || GetClientTeam(victim) != 3)
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker == 0 || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2)
	{
		return;
	}

	int zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	
	if (zombieclass != 5) 
	{
		Kills[attacker]++;
	}
}

bool IsValidClient(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return false;
	}
	if (!IsValidEntity(client))
	{
		return false;
	}
	return true;
}

void ClearStatsCounter()
{
	for (int i=1;i <= MaxClients;++i)
	{
		Crowns[i] = 0;
		Kills[i] = 0;
	}
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	if (!g_bRoundEndAnnounce)
	{
		if(CvarAnnounce & 4)
			PrintStats();
		g_bRoundEndAnnounce = true;
	}
}

void PrintStats()
{
	int survivor_index = 0;
	int[] survivor_clients = new int[MaxClients+1];
	int client;
	for (client=1;client <= MaxClients;++client)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != 2) continue;

		survivor_clients[survivor_index] = client;
		survivor_index++;
	}

	SortCustom1D(survivor_clients, survivor_index, SortByKillsDesc);

	CPrintToChatAll("{lightgreen}------------------------------");
	int frags;
	int crownscount;
	for (int i=0;i < survivor_index;++i)
	{
		client = survivor_clients[i];
		frags = Kills[client];
		crownscount = Crowns[client];
		PrintToChatAll("\x04%N \x03(Kills: \x01%i \x03| Crowns: \x01%i\x03)", client, frags, crownscount);
	}
	CPrintToChatAll("{lightgreen}------------------------------");
}

int SortByKillsDesc(int elem1, int elem2, const int[] array, Handle hndl)
{
	if (Kills[elem1] > Kills[elem2])
	{
		return -1;
	}
	if (Kills[elem2] > Kills[elem1])
	{
		return 1;
	}
	if (elem1 > elem2)
	{
		return -1;
	}
	if (elem2 > elem1)
	{
		return 1;
	}
	return 0;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	ClearStatsCounter();
	g_bRoundEndAnnounce = false;
}

void Crowned(int client)
{
	CreateTimer(0.1, Award, client, TIMER_FLAG_NO_MAPCHANGE);
	timerDeath[client] = 200;
}

Action Award(Handle timer, int client)
{
	if (!IsClientInGame(client)) return Plugin_Continue;

	timerDeath[client] -= 20;
	if (timerDeath[client] > 101)
	{
		EmitSoundToAll("player/orch_hit_Csharp_short.wav", client, 3, 140, 0, 1.0, timerDeath[client], -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		switch (timerDeath[client])
		{
			case 120:
			{
				CreateTimer(1.1, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 140:
			{
				CreateTimer(0.8, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 160:
			{
				CreateTimer(0.5, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			case 180:
			{
				CreateTimer(0.3, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
			default:
			{
				CreateTimer(1.3, Award, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	return Plugin_Continue;
}

Action Timer_PrintTopCrowns(Handle timer, int attacker)
{
	PrintTopCrowners(0);
	return Plugin_Continue;
}

void PrintTopCrowners(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);

	CPlayerCrownData CTopPlayer[TOP_NUMBER];
	int totalcrowns=0, Max_crowns, iCrowns, Max_index;
	bool bIgnore;
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	
	for(int current = 0; current < TOP_NUMBER; current++)
	{
		g_hData.GotoFirstSubKey(true);

		Max_crowns = 0;
		Max_index = 0;
		for (int index=1; index <= count ;++index, g_hData.GotoNextKey(true))
		{
			iCrowns = g_hData.GetNum("crown", 0);
			if(iCrowns <= 0) continue;

			if(current == 0)
			{
				totalcrowns += iCrowns;
			}
			else
			{
				bIgnore = false;
				for(int previous = 0; previous < current; previous++)
				{
					if(index == CTopPlayer[previous].m_iPosition)
					{
						if(current-1==previous) g_hData.GetString("name", CTopPlayer[previous].m_sName, sizeof(CPlayerCrownData::m_sName), "Unnamed");
						bIgnore = true;
						break;
					}
				}
				if(bIgnore) continue;
			}
			
			if(iCrowns > Max_crowns)
			{
				Max_crowns 	= iCrowns;
				Max_index 	= index;
			}
		}
		CTopPlayer[current].m_iCrowns 		= Max_crowns;
		CTopPlayer[current].m_iPosition 	= Max_index;
		g_hData.GoBack();
	}
	g_hData.GotoFirstSubKey(true);
	for (int index=1; index <= count ;++index, g_hData.GotoNextKey(true))
	{
		if(index == CTopPlayer[TOP_NUMBER-1].m_iPosition)
		{
			g_hData.GetString("name", CTopPlayer[TOP_NUMBER-1].m_sName, sizeof(CPlayerCrownData::m_sName), "Unnamed");
			break;
		}
	}

	Panel panel = new Panel();
	static char sBuffer[128];

	if(g_hCvar1v1Separate.BoolValue && Is1v1)
		FormatEx(sBuffer, sizeof(sBuffer), "Mejores Crowners de Witch en 1v1");
	else
		FormatEx(sBuffer, sizeof(sBuffer), "Top %d Mejores Crowners de Witch", TOP_NUMBER);
	
	panel.SetTitle(sBuffer);
	panel.DrawText("\n ");
	if (totalcrowns)
	{
		for (int i=0 ; i<TOP_NUMBER && i < count;++i)
		{
			FormatEx(sBuffer, sizeof(sBuffer), "%d crowns - %s", CTopPlayer[i].m_iCrowns, CTopPlayer[i].m_sName);
			panel.DrawItem(sBuffer);
		}
		panel.DrawText("\n ");
		FormatEx(sBuffer, sizeof(sBuffer), "Total de %d crowns en el servidor%s", totalcrowns, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
		panel.DrawText(sBuffer);
	}
	else
	{
		Format(sBuffer, sizeof(sBuffer), "No hay crowns en este servidor todavía%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
	}

	if(client == 0)
	{
		for (int player = 1; player<=MaxClients; ++player)
		{	
			if (IsClientInGame(player) && !IsFakeClient(player))
			{
				panel.Send(player, TopCrownPanelHandler, 8);
			}
		}
	}
	else 
	{
		panel.Send(client, TopCrownPanelHandler, 8);
	}

	delete panel;
}

Action Timer_Statistic(Handle timer, int attacker)
{
	if(g_hData == null) return Plugin_Continue;
	g_hData.Rewind();
	g_hData.JumpToKey("data", true);

	attacker = GetClientOfUserId(attacker);
	if(attacker > 0 && IsClientInGame(attacker))
	{
		static char clientname[32];
		GetClientName(attacker, clientname, 32);
		ReplaceString(clientname, 32, "'", "", true);
		ReplaceString(clientname, 32, "<", "", true);
		ReplaceString(clientname, 32, "{", "", true);
		ReplaceString(clientname, 32, "}", "", true);
		ReplaceString(clientname, 32, "\n", "", true);
		ReplaceString(clientname, 32, "\"", "", true);
		static char clientauth[32];
		GetClientAuthId(attacker, AuthId_Steam2, clientauth, 32);
		if (!g_hData.JumpToKey(clientauth, false))
		{
			g_hData.GoBack();
			g_hData.JumpToKey("info", true);
			int count = g_hData.GetNum("count", 0);
			count++;
			g_hData.SetNum("count", count);
			g_hData.GoBack();
			g_hData.JumpToKey("data", true);
			g_hData.JumpToKey(clientauth, true);
		}
		int crown = g_hData.GetNum("crown", 0);
		crown++;
		g_hData.SetNum("crown", crown);
		g_hData.SetString("name", clientname);
		g_hData.Rewind();

		if(g_hCvar1v1Separate.BoolValue && Is1v1)
			g_hData.ExportToFile(datafilepath_1v1);
		else
			g_hData.ExportToFile(datafilepath);
		
		if(CvarAnnounce & 8)
		{
			CPrintToChat(attacker, "[{green}Top Crowners{default}] ¡Ahora tienes {lightgreen}%d {green}crowns%s", crown, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : "!");
		}
	}

	return Plugin_Continue;
}

void PrintCrownsToClient(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, 32);
	g_hData.JumpToKey("data", false);
	g_hData.JumpToKey(auth, false);
	int crown = g_hData.GetNum("crown", 0);
	if (crown == 1)
	{
		CPrintToChat(client, "[{green}Top Crowners{default}] Tienes solo {lightgreen}1 {green}crown%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
	}
	else if (crown < 1)
	{
		CPrintToChat(client, "[{green}Top Crowners{default}] Aún no tienes {lightgreen}ningún {green}crowns%s", (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
	}
	else
	{
		CPrintToChat(client, "[{green}Top Crowners{default}] Tienes un total de {lightgreen}%d {green}crowns%s", crown, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
	}
	return;
}

void ShowCrownRank(int client)
{
	if(g_hData == null) return;
	g_hData.Rewind();

	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	int crown;
	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, 32);
	if (g_hData.JumpToKey(auth, false))
	{
		crown = g_hData.GetNum("crown", 0);
	}
	else
	{
		crown = 0;
	}
	int rank = TopTo(crown);
	CPrintToChat(client, "[{green}Top Crowners{default}] Ranking de {green}Crowns: {lightgreen}%d/%d%s", rank, count, (g_hCvar1v1Separate.BoolValue && Is1v1) ? " en 1v1." : ".");
}

int TopTo(int crowni)
{
	if(g_hData == null) return 0;
	g_hData.Rewind();
	
	g_hData.JumpToKey("info", false);
	int count = g_hData.GetNum("count", 0);
	int crown;
	g_hData.GoBack();
	g_hData.JumpToKey("data", false);
	g_hData.GotoFirstSubKey(true);
	int total;
	for (int i=0;i < count;++i)
	{
		crown = g_hData.GetNum("crown", 0);
		if (crown >= crowni)
		{
			total++;
		}
		g_hData.GotoNextKey(true);
	}
	return total;
}

int TopCrownPanelHandler(Handle menu, MenuAction action, int param1, int param2)
{
	return 0;
}