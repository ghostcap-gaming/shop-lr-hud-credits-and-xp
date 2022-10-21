#include <sourcemod>
#include <shop>
#include <lvl_ranks>
#include <queue>

#pragma semicolon 1
#pragma newdecls required

		// If the plugin is enabled
ConVar  g_cvPluginEnabled,
		// HUD message color start and end (effect)
		g_cvMessageColorGainStart,
		g_cvMessageColorGainEnd,
		g_cvMessageColorLoseStart,
		g_cvMessageColorLoseEnd,
		// the number of seconds to show the HUD message
		g_cvMessageDuration,
		// Position of the HUD message
		g_cvMessagePosition;

enum
{
	CURRENCY_CHANGED_XP,
	CURRENCY_CHANGED_CREDITS
}

enum struct UpdateMessage
{
	int currency_changed;
	int currency_new_amount;
	int currency_change_amount;
}

enum struct ClientData
{
	Handle message_timer;
	Queue update_messages;

	void init()
	{
		this.update_messages = new Queue(sizeof(UpdateMessage));
	}

	void clear()
	{
		delete this.message_timer;
		delete this.update_messages;
	}

	void AddMessage(int client, int currency_changed, int currency_new_amount, int currency_change_amount)
	{
		if (!this.update_messages)
		{
			return;
		}

		// Create Message
		UpdateMessage new_message;
		new_message.currency_changed = currency_changed;
		new_message.currency_new_amount = currency_new_amount;
		new_message.currency_change_amount = currency_change_amount;
		
		// PrintToChat(client, "currency_changed: %d, currency_new_amount: %d, currency_change_amount: %d", currency_changed, currency_new_amount, currency_change_amount);

		// Add to ArrayStack
		this.update_messages.PushArray(new_message);
		
		if (!this.message_timer)
		{
			this.ShowNextMessage(client);
			this.message_timer = CreateTimer(g_cvMessageDuration.FloatValue, Timer_CheckForNextMessage, GetClientUserId(client), TIMER_REPEAT);
		}
	}
	
	void ShowNextMessage(int client)
	{
		UpdateMessage message;
		this.update_messages.PopArray(message);
		
		float pos[2];
		GetUpdateMessagePos(pos);
		
		bool is_gaining = message.currency_change_amount > 0;
		
		int fx_colors[2][4];
		GetUpdateMessageFxColors(fx_colors, is_gaining);
		
		SetHudTextParamsEx(pos[0], pos[1], g_cvMessageDuration.FloatValue, fx_colors[1], fx_colors[0], 2, g_cvMessageDuration.FloatValue, 0.001, 0.001);
		ShowHudText(client, -1,
			"%s%d %s (%d → %d)",
			is_gaining ? "+" : "",
			message.currency_change_amount,
			message.currency_changed == CURRENCY_CHANGED_XP ? "XP" : "Credits",
			message.currency_new_amount - message.currency_change_amount,
			message.currency_new_amount
		);
	}
}

ClientData g_ClientsData[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "HUD Credits & XP",
	author = "LuqS", 
	description = "See money and xp earned on the top left of the screen", 
	version = "1.0.0.0", 
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	
	// ConVars
	g_cvPluginEnabled = CreateConVar("hud_cnx_enabled", "1", "Any non zero value will enable 'HUD Credits & XP' plugin");
	g_cvMessageColorGainStart = CreateConVar("hud_cnx_color_fx_gain_start", "168 235 52 255", "The start color for the HUD message effect");
	g_cvMessageColorGainEnd = CreateConVar("hud_cnx_color_fx_gain_end", "52 235 205 255", "The end color for the HUD message effect");
	g_cvMessageColorLoseStart = CreateConVar("hud_cnx_color_fx_lose_start", "235 52 52 255", "The start color for the HUD message effect");
	g_cvMessageColorLoseEnd = CreateConVar("hud_cnx_color_fx_lose_end", "235 52 201 255", "The end color for the HUD message effect");
	g_cvMessageDuration = CreateConVar("hud_cnx_duration", "2.0", "The number of seconds to show the HUD message");
	g_cvMessagePosition = CreateConVar("hud_cnx_position", "0.005 0.005", "The position of the HUD message");

	AutoExecConfig();
	// How to pick HUD message pos:
	/*   0.0 ---------------- X ---------------- 1.0
		  _________________________________________
   0.0   |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
		 |                                         |
	Y    |                                         |
		 |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
	|    |                                         |
   1.0   |_________________________________________| */
	
	// Hooks
	LR_Hook(LR_OnExpChanged, OnXPChanged);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientConnected(current_client);
		}
	}
}

public void OnClientConnected(int client)
{
	g_ClientsData[client].init();
}

public void OnClientDisconnect(int client)
{
	g_ClientsData[client].clear();
}

public void OnXPChanged(int client, int xp_given, int new_xp)
{
	//PrintToChat(client, "[OnXPChanged] client: %d | new_xp: %d | xp_given: %d", client, new_xp, xp_given);
	g_ClientsData[client].AddMessage(client, CURRENCY_CHANGED_XP, new_xp, xp_given);
}

public void Shop_OnCreditsGiven_Post(int client, int credits, int by_who)
{
	//PrintToChat(client, "[Shop_OnCreditsGiven_Post] client: %d | new credits: %d | credits given: %d", client, Shop_GetClientCredits(client), credits);
	g_ClientsData[client].AddMessage(client, CURRENCY_CHANGED_CREDITS, Shop_GetClientCredits(client), credits);
}

public void Shop_OnCreditsTaken_Post(int client, int credits, int by_who)
{
	//PrintToChat(client, "[Shop_OnCreditsTaken_Post] client: %d | new credits: %d | credits taken: %d", client, Shop_GetClientCredits(client), credits);
	g_ClientsData[client].AddMessage(client, CURRENCY_CHANGED_CREDITS, Shop_GetClientCredits(client), -credits);
}

Action Timer_CheckForNextMessage(Handle timer, any user_id)
{
	int client = GetClientOfUserId(user_id);
	
	if (!client || g_ClientsData[client].update_messages.Empty)
	{
		g_ClientsData[client].message_timer = null;
		return Plugin_Stop;
	}
	
	g_ClientsData[client].ShowNextMessage(client);
	return Plugin_Continue;
}

// Other

void GetUpdateMessagePos(float pos[2])
{
	char pos_str[16];
	g_cvMessagePosition.GetString(pos_str, sizeof(pos_str));
	
	int seperator_index = StrContains(pos_str, " ");
	
	if (seperator_index == -1)
	{
		pos[0] = pos[1] = 0.005;
		return;
	}
	
	pos[1] = StringToFloat(pos_str[seperator_index + 1]);
	pos_str[seperator_index] = '\0';
	pos[0] = StringToFloat(pos_str);
}

void GetUpdateMessageFxColors(int fx_colors[2][4], bool gain_cvar)
{
	char color_str[32];
	
	// get color start
	(gain_cvar ? g_cvMessageColorGainStart : g_cvMessageColorLoseStart).GetString(color_str, sizeof(color_str));
	GetColorsFromString(color_str, fx_colors[0]);
	
	// get color end
	(gain_cvar ? g_cvMessageColorGainEnd : g_cvMessageColorLoseEnd).GetString(color_str, sizeof(color_str));
	GetColorsFromString(color_str, fx_colors[1]);
}

void GetColorsFromString(char color_str[32], int fx_color[4])
{
	// get all colors
	fx_color[3] = GetColorFromString(color_str);
	fx_color[2] = GetColorFromString(color_str);
	fx_color[1] = GetColorFromString(color_str);
	fx_color[0] = StringToInt(color_str);
}

int GetColorFromString(char color_str[32])
{
	// get seperator
	int seperator_index = GetLastIndexOfChar(color_str, ' ');
	
	// default value if we fail.
	if (seperator_index == -1)
	{
		return 255;
	}
	
	// save so we can return this
	int color = StringToInt(color_str[seperator_index + 1]);
	
	// remove from string;
	color_str[seperator_index] = '\0';
	
	// return the color we saved
	return color;
}

int GetLastIndexOfChar(const char[] str, char ch)
{
	for (int current_char = strlen(str) - 1; current_char >= 0; current_char--)
	{
		if (str[current_char] == ch)
		{
			return current_char;
		}
	}
	
	return -1;
}