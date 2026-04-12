/*
 * Weapon Limits - humans-side rules only.
 *
 * CZ bots are restricted at the game DLL level via ReGameDLL cvars in
 * server.cfg (`bot_allow_snipers 0`, `bot_allow_shield 0`). That's the
 * ONLY layer that reliably blocks the items — Ham_Item_AddToPlayer and
 * fakemeta FM_GiveNamedItem both fire too late in the bot buy pipeline,
 * and the shield is a player flag with no entity at all.
 *
 * This plugin therefore focuses on the human-facing rules:
 *   - Limit humans to N AWPs per team
 *   - Block auto snipers (G3SG1, SG550) universally
 *   - Block tactical shield purchases via console command
 *   - Belt: strip AUG/SG552 from any bot that somehow ended up with one
 *     (e.g. picked up from a dead human)
 *
 * Cvars:
 *   wl_awp_per_team       max AWPs per team for HUMANS (default 3)
 *   wl_block_autosniper   1 = block G3SG1 and SG550 for everyone (default 1)
 *   wl_block_shield       1 = block tactical shield console buy (default 1)
 *   wl_bots_no_scoped     1 = safety net that strips scoped rifles from bots (default 1)
 */

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>

new g_cvarAwpLimit;
new g_cvarBlockAuto;
new g_cvarBlockShield;
new g_cvarBotsNoScoped;

public plugin_init()
{
    register_plugin("Weapon Limits", "2.0", "aiteklabs");

    g_cvarAwpLimit     = register_cvar("wl_awp_per_team",     "3");
    g_cvarBlockAuto    = register_cvar("wl_block_autosniper", "1");
    g_cvarBlockShield  = register_cvar("wl_block_shield",     "1");
    g_cvarBotsNoScoped = register_cvar("wl_bots_no_scoped",   "1");

    // Humans typing in console — bot console commands are filtered out
    register_clcmd("awp",           "cmd_buy_awp");
    register_clcmd("buy awp",       "cmd_buy_awp");
    register_clcmd("g3sg1",         "cmd_block_auto");
    register_clcmd("buy g3sg1",     "cmd_block_auto");
    register_clcmd("sg550",         "cmd_block_auto");
    register_clcmd("buy sg550",     "cmd_block_auto");
    register_clcmd("shield",        "cmd_block_shield");
    register_clcmd("buy shield",    "cmd_block_shield");
    register_clcmd("shieldgun",     "cmd_block_shield");
    register_clcmd("buy shieldgun", "cmd_block_shield");

    // Pickup blockers — fires when a dead player's weapon is picked up
    RegisterHam(Ham_Item_AddToPlayer, "weapon_awp",   "ham_add_awp",        0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_scout", "ham_add_bot_scoped", 0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_aug",   "ham_add_bot_scoped", 0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_sg552", "ham_add_bot_scoped", 0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_g3sg1", "ham_add_auto",       0);
    RegisterHam(Ham_Item_AddToPlayer, "weapon_sg550", "ham_add_auto",       0);
}

public cmd_block_auto(id)
{
    if (get_pcvar_num(g_cvarBlockAuto) != 1)
        return PLUGIN_CONTINUE;

    client_print(id, print_center, "Auto snipers (G3SG1/SG550) are disabled");
    client_print(id, print_chat,   "[WEAPONS] Auto snipers are disabled on this server.");
    return PLUGIN_HANDLED;
}

public cmd_block_shield(id)
{
    if (get_pcvar_num(g_cvarBlockShield) != 1)
        return PLUGIN_CONTINUE;

    client_print(id, print_center, "Tactical shield is disabled");
    client_print(id, print_chat,   "[WEAPONS] Tactical shield is disabled on this server.");
    return PLUGIN_HANDLED;
}

public cmd_buy_awp(id)
{
    if (!is_user_alive(id))
        return PLUGIN_CONTINUE;

    new limit = get_pcvar_num(g_cvarAwpLimit);
    if (limit <= 0)
        return PLUGIN_CONTINUE;

    new current = team_awp_count(id);
    if (current >= limit)
    {
        client_print(id, print_center, "Max %d AWPs per team (already %d)", limit, current);
        client_print(id, print_chat,   "[WEAPONS] Max %d AWPs per team.", limit);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public ham_add_auto(weapon_ent, id)
{
    if (get_pcvar_num(g_cvarBlockAuto) != 1)
        return HAM_IGNORED;
    return HAM_SUPERCEDE;
}

public ham_add_awp(weapon_ent, id)
{
    if (!is_user_alive(id))
        return HAM_IGNORED;

    // Bots are blocked by bot_allow_snipers 0 in server.cfg, but this Ham
    // catches the case where a bot picks up an AWP dropped on the ground.
    if (is_user_bot(id) && get_pcvar_num(g_cvarBotsNoScoped) == 1)
        return HAM_SUPERCEDE;

    new limit = get_pcvar_num(g_cvarAwpLimit);
    if (limit <= 0)
        return HAM_IGNORED;

    new current = team_awp_count(id);
    if (current >= limit)
    {
        client_print(id, print_center, "Team AWP limit reached (%d)", limit);
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

// Scout / AUG / SG552 — humans can use them, bots cannot
public ham_add_bot_scoped(weapon_ent, id)
{
    if (is_user_bot(id) && get_pcvar_num(g_cvarBotsNoScoped) == 1)
        return HAM_SUPERCEDE;
    return HAM_IGNORED;
}

team_awp_count(exclude_id)
{
    new CsTeams:team = cs_get_user_team(exclude_id);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return 0;

    new players[32], num;
    get_players(players, num, "a");

    new count = 0;
    for (new i = 0; i < num; i++)
    {
        if (players[i] == exclude_id)
            continue;
        if (cs_get_user_team(players[i]) != team)
            continue;
        if (user_has_weapon(players[i], CSW_AWP))
            count++;
    }
    return count;
}
