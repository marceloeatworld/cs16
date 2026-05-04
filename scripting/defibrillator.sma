// Defibrillator: every player gets defibs at round start and can revive
// the closest dead teammate within range.
//
// Commands: /defib, /medic, /heal (chat or team chat)
//
// Cvars:
//   df_enabled    1     plugin master switch
//   df_count      2     defibs per player per round (refreshed at Round_Start)
//   df_range      400.0 max distance (units) between medic and dead body
//                       (0 = unlimited)
//   df_cooldown   3.0   seconds between successive uses
//   df_health     100   HP after revive (<=0 = fall back to fe_health)
//   df_show_hud   1     show "Defib: N" in the bottom-left HUD
//   df_skip_bots  1     1 = ignore dead bots in the search (don't waste defibs)
//
// The revived teammate spawns at the medic's position with HP/armor/money
// matching the fe_* full-equip cvars. Defib is consumed only on success.

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fakemeta>

#define TASK_HUD   4000
#define TASK_TELE  4100
#define TASK_REEQ  4200

new g_defibs[33];
new Float:g_lastUse[33];
new Float:g_deathOrigin[33][3];
new bool:g_hasDeath[33];
new g_pendingMedic[33];
new bool:g_gotInitial[33];

new g_cvarEnabled, g_cvarCount, g_cvarRange, g_cvarCooldown;
new g_cvarHealth, g_cvarShowHud, g_cvarSkipBots;

public plugin_init()
{
    register_plugin("Defibrillator", "1.0", "aiteklabs");

    g_cvarEnabled  = register_cvar("df_enabled",   "1");
    g_cvarCount    = register_cvar("df_count",     "2");
    g_cvarRange    = register_cvar("df_range",     "400.0");
    g_cvarCooldown = register_cvar("df_cooldown",  "3.0");
    g_cvarHealth   = register_cvar("df_health",    "100");
    g_cvarShowHud  = register_cvar("df_show_hud",  "1");
    g_cvarSkipBots = register_cvar("df_skip_bots", "1");

    RegisterHam(Ham_Spawn,  "player", "OnSpawnPost",    1);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled", 1);
    register_logevent("OnRoundStart", 2, "1=Round_Start");

    register_clcmd("say /defib",       "cmd_defib");
    register_clcmd("say_team /defib",  "cmd_defib");
    register_clcmd("say /medic",       "cmd_defib");
    register_clcmd("say_team /medic",  "cmd_defib");
    register_clcmd("say /heal",        "cmd_defib");
    register_clcmd("say_team /heal",   "cmd_defib");

    set_task(1.0, "task_show_hud", TASK_HUD, _, _, "b");
}

public client_putinserver(id)
{
    g_defibs[id] = 0;
    g_lastUse[id] = 0.0;
    g_hasDeath[id] = false;
    g_pendingMedic[id] = 0;
    g_gotInitial[id] = false;
}

public client_disconnected(id)
{
    g_defibs[id] = 0;
    g_hasDeath[id] = false;
    g_pendingMedic[id] = 0;
    g_gotInitial[id] = false;
    remove_task(id + TASK_TELE);
    remove_task(id + TASK_REEQ);
}

public OnSpawnPost(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
        return;
    if (get_pcvar_num(g_cvarEnabled) != 1)
        return;

    g_hasDeath[id] = false;

    // First spawn after connect (mid-round joiners get one straight away).
    // Subsequent refills happen at Round_Start; defib counts do NOT refresh
    // on revives, otherwise a chain of revives would be infinite.
    if (!g_gotInitial[id])
    {
        new count = get_pcvar_num(g_cvarCount);
        if (count > 0)
            g_defibs[id] = count;
        g_gotInitial[id] = true;
    }
}

public OnPlayerKilled(victim, attacker, shouldgib)
{
    if (victim < 1 || victim > 32)
        return;

    new Float:o[3];
    pev(victim, pev_origin, o);
    g_deathOrigin[victim][0] = o[0];
    g_deathOrigin[victim][1] = o[1];
    g_deathOrigin[victim][2] = o[2];
    g_hasDeath[victim] = true;
}

public OnRoundStart()
{
    if (get_pcvar_num(g_cvarEnabled) != 1)
        return;

    new count = get_pcvar_num(g_cvarCount);
    if (count <= 0)
        return;

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_connected(i)) continue;
        if (is_user_bot(i)) continue;
        g_defibs[i] = count;
        g_lastUse[i] = 0.0;
    }
}

public cmd_defib(id)
{
    if (get_pcvar_num(g_cvarEnabled) != 1)
        return PLUGIN_HANDLED;

    if (!is_user_alive(id))
    {
        client_print(id, print_chat, "[DEFIB] You must be alive to revive.");
        return PLUGIN_HANDLED;
    }
    if (is_user_bot(id))
        return PLUGIN_HANDLED;

    if (g_defibs[id] <= 0)
    {
        client_print(id, print_chat, "[DEFIB] No defibrillator left this round.");
        return PLUGIN_HANDLED;
    }

    new Float:now = get_gametime();
    new Float:cd  = get_pcvar_float(g_cvarCooldown);
    if (cd > 0.0 && (now - g_lastUse[id]) < cd)
    {
        client_print(id, print_chat, "[DEFIB] Cooldown: %.1fs", cd - (now - g_lastUse[id]));
        return PLUGIN_HANDLED;
    }

    new CsTeams:my_team = cs_get_user_team(id);
    if (my_team != CS_TEAM_T && my_team != CS_TEAM_CT)
    {
        client_print(id, print_chat, "[DEFIB] Pick a team first.");
        return PLUGIN_HANDLED;
    }

    new Float:my_origin[3];
    pev(id, pev_origin, my_origin);

    new Float:max_range    = get_pcvar_float(g_cvarRange);
    new Float:max_range_sq = max_range * max_range;
    new bool:limited       = (max_range > 0.0);
    new bool:skip_bots     = (get_pcvar_num(g_cvarSkipBots) == 1);

    new best = 0;
    new Float:best_dist_sq = 1.0e9;

    for (new t = 1; t <= 32; t++)
    {
        if (t == id) continue;
        if (!is_user_connected(t)) continue;
        if (is_user_alive(t)) continue;
        if (skip_bots && is_user_bot(t)) continue;
        if (cs_get_user_team(t) != my_team) continue;
        if (!g_hasDeath[t]) continue;

        new Float:dx = my_origin[0] - g_deathOrigin[t][0];
        new Float:dy = my_origin[1] - g_deathOrigin[t][1];
        new Float:dz = my_origin[2] - g_deathOrigin[t][2];
        new Float:dist_sq = dx * dx + dy * dy + dz * dz;

        if (limited && dist_sq > max_range_sq) continue;

        if (dist_sq < best_dist_sq)
        {
            best = t;
            best_dist_sq = dist_sq;
        }
    }

    if (best == 0)
    {
        client_print(id, print_chat, "[DEFIB] No revivable teammate within range.");
        return PLUGIN_HANDLED;
    }

    g_defibs[id]--;
    g_lastUse[id] = now;
    g_pendingMedic[best] = id;
    g_hasDeath[best] = false;

    ExecuteHamB(Ham_CS_RoundRespawn, best);
    set_task(0.1, "task_teleport_revived", best + TASK_TELE);
    set_task(0.2, "task_post_revive_equip", best + TASK_REEQ);

    new myname[32], tname[32];
    get_user_name(id,   myname, charsmax(myname));
    get_user_name(best, tname,  charsmax(tname));
    client_print(0, print_chat, "[DEFIB] %s revived %s.", myname, tname);

    return PLUGIN_HANDLED;
}

public task_teleport_revived(taskid)
{
    new id = taskid - TASK_TELE;
    if (!is_user_alive(id))
    {
        g_pendingMedic[id] = 0;
        return;
    }

    new medic = g_pendingMedic[id];
    g_pendingMedic[id] = 0;
    if (medic <= 0 || !is_user_connected(medic) || !is_user_alive(medic))
        return;

    new Float:o[3];
    pev(medic, pev_origin, o);
    o[2] += 1.0;  // tiny Z bump to dodge floor clip after SetOrigin

    engfunc(EngFunc_SetOrigin, id, o);
}

public task_post_revive_equip(taskid)
{
    new id = taskid - TASK_REEQ;
    if (!is_user_alive(id)) return;

    new hp = get_pcvar_num(g_cvarHealth);
    if (hp <= 0)
        hp = get_cvar_num("fe_health");
    if (hp > 0)
        set_user_health(id, hp);

    if (get_cvar_num("fe_armor") == 1)
        cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM);

    new money = get_cvar_num("fe_money");
    if (money > 0)
        cs_set_user_money(id, money, 1);
}

public task_show_hud()
{
    if (get_pcvar_num(g_cvarShowHud) != 1) return;
    if (get_pcvar_num(g_cvarEnabled) != 1) return;

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_alive(i)) continue;
        if (is_user_bot(i)) continue;
        if (g_defibs[i] <= 0) continue;

        // Channel 4 — avoids stomping the standard hud channels (0-3).
        set_hudmessage(0, 200, 0, 0.02, 0.85, 0, 0.0, 1.1, 0.0, 0.0, 4);
        show_hudmessage(i, "Defib: %d", g_defibs[i]);
    }
}
