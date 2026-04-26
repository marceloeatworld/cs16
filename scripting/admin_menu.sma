// Admin menu driven by chat commands (no number-key binds required).
// All commands below check the relevant ADMIN_* flag from users.ini.
//
// /admin /kick /ban /slap /team /map /votemap /restrict /restart /revive /bot /info
// /fx /night /day /dusk /dark /ff /grav /speed

#include <amxmodx>
#include <amxmisc>
#include <engine>

#define KEYS_ALL 1023

public plugin_init()
{
    register_plugin("Admin Menu", "1.0", "aiteklabs");

    register_clcmd("amx_menu",        "cmd_show_help");
    register_clcmd("amxmodmenu",      "cmd_show_help");
    register_clcmd("say /admin",      "cmd_show_help");
    register_clcmd("say_team /admin", "cmd_show_help");
    register_clcmd("say /cmds",       "cmd_show_help");

    register_clcmd("say /kick",     "cmd_kick");
    register_clcmd("say /ban",      "cmd_ban");
    register_clcmd("say /slap",     "cmd_slap");
    register_clcmd("say /team",     "cmd_team");
    register_clcmd("say /map",      "cmd_map");
    register_clcmd("say /votemap",  "cmd_votemap");
    register_clcmd("say /restrict", "cmd_restrict");
    register_clcmd("say /restart",  "cmd_restart");
    register_clcmd("say /info",     "cmd_info");
    register_clcmd("say /bot",      "cmd_bot_menu");

    register_clcmd("say /fx",    "cmd_fx_menu");
    register_clcmd("say /night", "cmd_night");
    register_clcmd("say /day",   "cmd_day");
    register_clcmd("say /dusk",  "cmd_dusk");
    register_clcmd("say /dark",  "cmd_dark");
    register_clcmd("say /ff",    "cmd_ff_toggle");
    register_clcmd("say /grav",  "cmd_grav_menu");
    register_clcmd("say /speed", "cmd_speed_menu");

    register_menucmd(register_menuid("AitekBots"),  KEYS_ALL, "handle_bots");
    register_menucmd(register_menuid("AitekFX"),    KEYS_ALL, "handle_fx");
    register_menucmd(register_menuid("AitekLight"), KEYS_ALL, "handle_light");
    register_menucmd(register_menuid("AitekGrav"),  KEYS_ALL, "handle_grav");
    register_menucmd(register_menuid("AitekSpeed"), KEYS_ALL, "handle_speed");
}

public cmd_show_help(id)
{
    if (!(get_user_flags(id) & ADMIN_MENU))
    {
        client_print(id, print_chat, "[ADMIN] No access.");
        return PLUGIN_HANDLED;
    }

    client_print(id, print_chat, "=== [AITEKLABS] Admin Commands ===");
    client_print(id, print_chat, "/kick - /ban - /slap - /team - /map - /votemap");
    client_print(id, print_chat, "/restrict - /restart - /revive - /bot - /info");
    client_print(id, print_chat, "/fx - /night - /day - /dusk - /dark - /ff - /grav - /speed");
    client_print(id, print_chat, "/de /cs /fy /aim /awp /rats /ka /dr - map votes");
    return PLUGIN_HANDLED;
}

public cmd_kick(id)
{
    if (!(get_user_flags(id) & ADMIN_KICK)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_kickmenu");
    return PLUGIN_HANDLED;
}
public cmd_ban(id)
{
    if (!(get_user_flags(id) & ADMIN_BAN)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_banmenu");
    return PLUGIN_HANDLED;
}
public cmd_slap(id)
{
    if (!(get_user_flags(id) & ADMIN_SLAY)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_slapmenu");
    return PLUGIN_HANDLED;
}
public cmd_team(id)
{
    if (!(get_user_flags(id) & ADMIN_KICK)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_teammenu");
    return PLUGIN_HANDLED;
}
public cmd_map(id)
{
    if (!(get_user_flags(id) & ADMIN_MAP)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_mapmenu");
    return PLUGIN_HANDLED;
}
public cmd_votemap(id)
{
    if (!(get_user_flags(id) & ADMIN_VOTE)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_votemapmenu");
    return PLUGIN_HANDLED;
}
public cmd_restrict(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    client_cmd(id, "amx_restmenu");
    return PLUGIN_HANDLED;
}
public cmd_restart(id)
{
    if (!(get_user_flags(id) & ADMIN_RCON)) return PLUGIN_HANDLED;
    server_cmd("sv_restart 1");
    client_print(id, print_chat, "[ADMIN] Round restarting...");
    return PLUGIN_HANDLED;
}
public cmd_info(id)
{
    new players[32], num, bots = 0;
    get_players(players, num, "ch");
    for (new i = 0; i < num; i++)
        if (is_user_bot(players[i])) bots++;
    new mapname[32];
    get_mapname(mapname, charsmax(mapname));
    client_print(id, print_chat, "[INFO] Map: %s | Players: %d (%d bots) | AMX 1.10", mapname, num, bots);
    return PLUGIN_HANDLED;
}

public cmd_bot_menu(id)
{
    if (!(get_user_flags(id) & ADMIN_MENU)) return PLUGIN_HANDLED;

    new menu[512];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Bot Settings\w^n^n\
\y1. \wAdd Bot T^n\
\y2. \wAdd Bot CT^n\
\y3. \wRemove 1 Bot^n\
\y4. \wRemove All^n\
\y5. \wQuota 6 (fill mode)^n\
\y6. \wQuota 10 (fill mode)^n\
\y7. \wDisable bots^n\
\y8. \wStatus^n^n\
\y0. \wExit");

    show_menu(id, KEYS_ALL, menu, -1, "AitekBots");
    return PLUGIN_HANDLED;
}

public handle_bots(id, key)
{
    switch (key)
    {
        case 0: { server_cmd("bot_add_t");  client_print(id, print_chat, "[BOTS] Added T bot"); }
        case 1: { server_cmd("bot_add_ct"); client_print(id, print_chat, "[BOTS] Added CT bot"); }
        case 2: { server_cmd("bot_kick");   client_print(id, print_chat, "[BOTS] Kicked 1 bot"); }
        case 3:
        {
            for (new i = 0; i < 10; i++)
                server_cmd("bot_kick");
            client_print(id, print_chat, "[BOTS] Kicked all bots");
        }
        case 4: { server_cmd("bot_quota 6");  client_print(id, print_chat, "[BOTS] Quota set to 6"); }
        case 5: { server_cmd("bot_quota 10"); client_print(id, print_chat, "[BOTS] Quota set to 10"); }
        case 6: { server_cmd("bot_quota 0");  client_print(id, print_chat, "[BOTS] Disabled"); }
        case 7:
        {
            new players[32], num, bots;
            get_players(players, num);
            for (new i = 0; i < num; i++)
                if (is_user_bot(players[i])) bots++;
            client_print(id, print_chat, "[BOTS] %d bots | %d humans", bots, num - bots);
        }
    }
    return PLUGIN_HANDLED;
}

public cmd_fx_menu(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;

    new menu[512];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Server FX\w^n^n\
\y1. \wLighting (day/night)^n\
\y2. \wGravity^n\
\y3. \wMovement speed^n\
\y4. \wToggle friendly fire^n\
\y5. \wToggle flashlight^n\
\y6. \wRestart round^n^n\
\y0. \wExit");

    show_menu(id, KEYS_ALL, menu, -1, "AitekFX");
    return PLUGIN_HANDLED;
}

public handle_fx(id, key)
{
    switch (key)
    {
        case 0: { cmd_light_menu(id); }
        case 1: { cmd_grav_menu(id); }
        case 2: { cmd_speed_menu(id); }
        case 3: { cmd_ff_toggle(id); }
        case 4:
        {
            new v = get_cvar_num("mp_flashlight") ? 0 : 1;
            server_cmd("mp_flashlight %d", v);
            client_print(id, print_chat, "[FX] Flashlight %s", v ? "ON" : "OFF");
        }
        case 5: { cmd_restart(id); }
    }
    return PLUGIN_HANDLED;
}

// set_lights() takes a string of characters a-z: a=pitch black, m=normal day,
// z=super bright. Multi-char strings create flickering/strobe animations.
public cmd_light_menu(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;

    new menu[512];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Map Lighting\w^n^n\
\y1. \wDay (normal)^n\
\y2. \wDusk^n\
\y3. \wNight^n\
\y4. \wBlackout (flashlight only)^n\
\y5. \wStrobe (party)^n\
\y6. \wFlicker (horror)^n^n\
\y0. \wExit");

    show_menu(id, KEYS_ALL, menu, -1, "AitekLight");
    return PLUGIN_HANDLED;
}

public handle_light(id, key)
{
    switch (key)
    {
        case 0: { apply_light(id, "m",                           "Day");      }
        case 1: { apply_light(id, "g",                           "Dusk");     }
        case 2: { apply_light(id, "c",                           "Night");    }
        case 3: { apply_light(id, "a",                           "Blackout"); }
        case 4: { apply_light(id, "mmamammmmammamamaaamammma",   "Strobe");   }
        case 5: { apply_light(id, "mmnmmommommnonmmonqnmmo",     "Flicker");  }
    }
    return PLUGIN_HANDLED;
}

apply_light(id, const pattern[], const label[])
{
    set_lights(pattern);
    client_print(0, print_chat, "[FX] Lighting: %s (by admin)", label);
    new name[32]; get_user_name(id, name, charsmax(name));
    log_amx("[FX] %s changed lighting to %s (%s)", name, label, pattern);
}

public cmd_day(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    apply_light(id, "m", "Day");
    return PLUGIN_HANDLED;
}
public cmd_dusk(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    apply_light(id, "g", "Dusk");
    return PLUGIN_HANDLED;
}
public cmd_night(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    apply_light(id, "c", "Night");
    return PLUGIN_HANDLED;
}
public cmd_dark(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    apply_light(id, "a", "Blackout");
    return PLUGIN_HANDLED;
}

public cmd_grav_menu(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;

    new menu[512];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Gravity\w^n^n\
\y1. \wMoon (200)^n\
\y2. \wLow (400)^n\
\y3. \wNormal (800)^n\
\y4. \wHeavy (1200)^n\
\y5. \wLead (1600)^n^n\
\y0. \wExit");

    show_menu(id, KEYS_ALL, menu, -1, "AitekGrav");
    return PLUGIN_HANDLED;
}

public handle_grav(id, key)
{
    new values[] = { 200, 400, 800, 1200, 1600 };
    if (key >= 0 && key < sizeof(values))
    {
        set_cvar_num("sv_gravity", values[key]);
        client_print(0, print_chat, "[FX] Gravity set to %d", values[key]);
    }
    return PLUGIN_HANDLED;
}

public cmd_speed_menu(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;

    new menu[512];
    formatex(menu, charsmax(menu), "\y[AITEKLABS] Movement Speed\w^n^n\
\y1. \wSlow (200)^n\
\y2. \wNormal (320)^n\
\y3. \wFast (500)^n\
\y4. \wTurbo (800)^n^n\
\y0. \wExit");

    show_menu(id, KEYS_ALL, menu, -1, "AitekSpeed");
    return PLUGIN_HANDLED;
}

public handle_speed(id, key)
{
    new values[] = { 200, 320, 500, 800 };
    if (key >= 0 && key < sizeof(values))
    {
        set_cvar_num("sv_maxspeed", values[key]);
        client_print(0, print_chat, "[FX] Max speed set to %d", values[key]);
    }
    return PLUGIN_HANDLED;
}

public cmd_ff_toggle(id)
{
    if (!(get_user_flags(id) & ADMIN_CFG)) return PLUGIN_HANDLED;
    new v = get_cvar_num("mp_friendlyfire") ? 0 : 1;
    set_cvar_num("mp_friendlyfire", v);
    client_print(0, print_chat, "[FX] Friendly fire %s", v ? "ON" : "OFF");
    return PLUGIN_HANDLED;
}
