// Defibrillator: walk near a dead teammate and HOLD E to revive them.
//
// UX, mirroring the classic Cheap_Suit "Revival Kit" pattern:
//   - When an alive teammate is within `df_range` of a dead body and has line
//     of sight to it, a yellow HUD prompt "[E] Hold to revive <name>" appears
//     and the CS "rescue" status icon flashes on the medic's screen.
//   - Holding +use (E) starts the CS defuse-style progress bar (BarTime user
//     message) for `df_hold_time` seconds and plays a medkit sound.
//   - Releasing E or breaking line of sight cancels the revive, clears the
//     bar and plays the failure sound.
//   - On completion the dead teammate respawns at the medic's position with
//     fe_health / fe_armor / fe_money applied, sees a black-to-clear screen
//     fade, and the medic loses one defib.
//
// Each player gets `df_count` defibs at Round_Start. Counts do NOT refresh
// on revive-spawns (otherwise revive chains would be infinite).
//
// Cvars:
//   df_enabled    1     plugin master switch
//   df_count      2     defibs per player per round
//   df_range      150.0 max distance (units) between medic and dead body
//   df_hold_time  2.5   seconds the medic must hold E to complete the revive
//   df_health     100   HP after revive (<=0 = fall back to fe_health)
//   df_show_hud   1     show "Defib: N" in the corner + the [E] prompt
//   df_skip_bots  1     1 = ignore dead bots in the search

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fakemeta>

#define TASK_TICK    4500
#define TASK_HUD     4000
#define TASK_TELE    4100
#define TASK_REEQ    4200

#define TICK_INTERVAL 0.1

#define SND_REVIVE_START   "items/medshot4.wav"
#define SND_REVIVE_SUCCESS "items/smallmedkit2.wav"
#define SND_REVIVE_CANCEL  "items/medshotno1.wav"

new g_defibs[33];
new Float:g_deathOrigin[33][3];
new bool:g_hasDeath[33];
new bool:g_gotInitial[33];

// Revive in progress
new g_reviveTarget[33];        // 0 = not currently reviving anyone
new Float:g_reviveCompleteAt[33];
new g_pendingMedic[33];        // for the post-respawn teleport task
new bool:g_iconShown[33];      // dedup for the StatusIcon flashing message

new g_msgBarTime, g_msgStatusIcon, g_msgScreenFade;

new g_cvarEnabled, g_cvarCount, g_cvarRange;
new g_cvarHoldTime, g_cvarHealth, g_cvarShowHud, g_cvarSkipBots;

public plugin_precache()
{
    precache_sound(SND_REVIVE_START);
    precache_sound(SND_REVIVE_SUCCESS);
    precache_sound(SND_REVIVE_CANCEL);
}

public plugin_init()
{
    register_plugin("Defibrillator", "2.1", "aiteklabs");

    g_cvarEnabled  = register_cvar("df_enabled",   "1");
    g_cvarCount    = register_cvar("df_count",     "2");
    g_cvarRange    = register_cvar("df_range",     "150.0");
    g_cvarHoldTime = register_cvar("df_hold_time", "2.5");
    g_cvarHealth   = register_cvar("df_health",    "100");
    g_cvarShowHud  = register_cvar("df_show_hud",  "1");
    g_cvarSkipBots = register_cvar("df_skip_bots", "1");

    RegisterHam(Ham_Spawn,  "player", "OnSpawnPost",    1);
    RegisterHam(Ham_Killed, "player", "OnPlayerKilled", 1);
    register_logevent("OnRoundStart", 2, "1=Round_Start");

    g_msgBarTime    = get_user_msgid("BarTime");
    g_msgStatusIcon = get_user_msgid("StatusIcon");
    g_msgScreenFade = get_user_msgid("ScreenFade");

    set_task(TICK_INTERVAL, "task_tick",     TASK_TICK, _, _, "b");
    set_task(1.0,           "task_show_hud", TASK_HUD,  _, _, "b");
}

public client_putinserver(id)
{
    reset_player_state(id);
}

public client_disconnected(id)
{
    reset_player_state(id);
    remove_task(id + TASK_TELE);
    remove_task(id + TASK_REEQ);
}

reset_player_state(id)
{
    g_defibs[id] = 0;
    g_hasDeath[id] = false;
    g_pendingMedic[id] = 0;
    g_gotInitial[id] = false;
    g_reviveTarget[id] = 0;
    g_reviveCompleteAt[id] = 0.0;
    g_iconShown[id] = false;
}

public OnSpawnPost(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
        return;
    if (get_pcvar_num(g_cvarEnabled) != 1)
        return;

    g_hasDeath[id] = false;
    g_reviveTarget[id] = 0;

    // First spawn after connect - give defibs straight away (mid-round
    // joiners). Subsequent refills happen at Round_Start.
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
    if (victim < 1 || victim > 32) return;

    new Float:o[3];
    pev(victim, pev_origin, o);
    g_deathOrigin[victim][0] = o[0];
    g_deathOrigin[victim][1] = o[1];
    g_deathOrigin[victim][2] = o[2];
    g_hasDeath[victim] = true;
}

public OnRoundStart()
{
    if (get_pcvar_num(g_cvarEnabled) != 1) return;

    new count = get_pcvar_num(g_cvarCount);
    if (count <= 0) return;

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_connected(i)) continue;
        if (is_user_bot(i)) continue;
        g_defibs[i] = count;
        g_reviveTarget[i] = 0;
    }
}

public task_tick()
{
    if (get_pcvar_num(g_cvarEnabled) != 1) return;

    new Float:now          = get_gametime();
    new Float:max_range    = get_pcvar_float(g_cvarRange);
    new Float:max_range_sq = max_range * max_range;
    new Float:hold_time    = get_pcvar_float(g_cvarHoldTime);
    new bool:skip_bots     = (get_pcvar_num(g_cvarSkipBots) == 1);
    new bool:show_hud      = (get_pcvar_num(g_cvarShowHud)  == 1);

    for (new id = 1; id <= 32; id++)
    {
        if (!is_user_alive(id))   continue;
        if (is_user_bot(id))      continue;
        if (g_defibs[id] <= 0)    continue;

        new CsTeams:team = cs_get_user_team(id);
        if (team != CS_TEAM_T && team != CS_TEAM_CT) continue;

        new target = find_revivable(id, team, max_range_sq, skip_bots);
        new bool:is_using = (pev(id, pev_button) & IN_USE) != 0;

        if (target == 0)
        {
            set_rescue_icon(id, false);
            if (g_reviveTarget[id] != 0)
                cancel_revive(id);
            continue;
        }

        set_rescue_icon(id, true);

        if (show_hud)
        {
            new tname[32];
            get_user_name(target, tname, charsmax(tname));
            // Channel 3, refreshed each tick (hold slightly > tick interval
            // so the prompt looks continuous instead of flickering).
            set_hudmessage(255, 200, 0, -1.0, 0.72, 0, 0.0, TICK_INTERVAL + 0.15, 0.0, 0.0, 3);
            show_hudmessage(id, "[E] Hold to revive %s", tname);
        }

        if (is_using)
        {
            if (g_reviveTarget[id] != target)
                start_revive(id, target, hold_time);
            else if (now >= g_reviveCompleteAt[id])
                complete_revive(id);
        }
        else if (g_reviveTarget[id] != 0)
        {
            cancel_revive(id);
        }
    }
}

find_revivable(medic, CsTeams:team, Float:max_range_sq, bool:skip_bots)
{
    new Float:eye[3], Float:view_ofs[3];
    pev(medic, pev_origin,   eye);
    pev(medic, pev_view_ofs, view_ofs);
    eye[0] += view_ofs[0];
    eye[1] += view_ofs[1];
    eye[2] += view_ofs[2];

    new best = 0;
    new Float:best_dist_sq = max_range_sq + 1.0;

    for (new t = 1; t <= 32; t++)
    {
        if (t == medic)                    continue;
        if (!is_user_connected(t))         continue;
        if (is_user_alive(t))              continue;
        if (skip_bots && is_user_bot(t))   continue;
        if (cs_get_user_team(t) != team)   continue;
        if (!g_hasDeath[t])                continue;

        new Float:dx = eye[0] - g_deathOrigin[t][0];
        new Float:dy = eye[1] - g_deathOrigin[t][1];
        new Float:dz = eye[2] - g_deathOrigin[t][2];
        new Float:dist_sq = dx * dx + dy * dy + dz * dz;

        if (dist_sq > max_range_sq)  continue;
        if (dist_sq >= best_dist_sq) continue;

        // LOS check: trace from medic eyes to ~torso height of corpse.
        // IGNORE_MONSTERS skips player/bot entities so only world walls block.
        new Float:body[3];
        body[0] = g_deathOrigin[t][0];
        body[1] = g_deathOrigin[t][1];
        body[2] = g_deathOrigin[t][2] + 16.0;

        engfunc(EngFunc_TraceLine, eye, body, IGNORE_MONSTERS, medic, 0);
        new Float:fraction;
        get_tr2(0, TR_flFraction, fraction);
        if (fraction < 0.95) continue;

        best = t;
        best_dist_sq = dist_sq;
    }

    return best;
}

start_revive(medic, target, Float:hold_time)
{
    g_reviveTarget[medic]     = target;
    g_reviveCompleteAt[medic] = get_gametime() + hold_time;

    // CS defuse-style progress bar
    message_begin(MSG_ONE, g_msgBarTime, _, medic);
    write_byte(floatround(hold_time));
    message_end();

    emit_sound(medic, CHAN_ITEM, SND_REVIVE_START, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

cancel_revive(medic)
{
    new bool:was_active = (g_reviveTarget[medic] != 0);
    g_reviveTarget[medic] = 0;

    // Clear the progress bar
    message_begin(MSG_ONE, g_msgBarTime, _, medic);
    write_byte(0);
    message_end();

    if (was_active && is_user_alive(medic))
        emit_sound(medic, CHAN_ITEM, SND_REVIVE_CANCEL, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

complete_revive(medic)
{
    new target = g_reviveTarget[medic];
    if (target <= 0 || !is_user_connected(target) || is_user_alive(target))
    {
        cancel_revive(medic);
        return;
    }

    g_defibs[medic]--;
    g_reviveTarget[medic] = 0;
    g_pendingMedic[target] = medic;
    g_hasDeath[target] = false;

    // Clear any lingering progress bar on the medic.
    message_begin(MSG_ONE, g_msgBarTime, _, medic);
    write_byte(0);
    message_end();

    ExecuteHamB(Ham_CS_RoundRespawn, target);
    set_task(0.1, "task_teleport_revived",  target + TASK_TELE);
    set_task(0.2, "task_post_revive_equip", target + TASK_REEQ);

    emit_sound(medic, CHAN_ITEM, SND_REVIVE_SUCCESS, 1.0, ATTN_NORM, 0, PITCH_NORM);

    new myname[32], tname[32];
    get_user_name(medic,  myname, charsmax(myname));
    get_user_name(target, tname,  charsmax(tname));
    client_print(0, print_chat, "[DEFIB] %s revived %s.", myname, tname);
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

    // "Waking up" black-to-clear fade for the revived player.
    message_begin(MSG_ONE, g_msgScreenFade, _, id);
    write_short(1 << 12);   // ~1s fade duration
    write_short(0);         // no hold
    write_short(0x0000);    // FFADE_IN: start opaque, fade to clear
    write_byte(0);          // r
    write_byte(0);          // g
    write_byte(0);          // b
    write_byte(255);        // alpha at start
    message_end();

    emit_sound(id, CHAN_AUTO, SND_REVIVE_SUCCESS, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

set_rescue_icon(id, bool:show)
{
    if (g_iconShown[id] == show) return;
    g_iconShown[id] = show;

    // StatusIcon: byte 0 = hide, 2 = flash. Followed by sprite name and RGB.
    message_begin(MSG_ONE, g_msgStatusIcon, _, id);
    write_byte(show ? 2 : 0);
    write_string("rescue");
    write_byte(0);
    write_byte(show ? 160 : 0);
    write_byte(0);
    message_end();
}

public task_show_hud()
{
    if (get_pcvar_num(g_cvarShowHud) != 1) return;
    if (get_pcvar_num(g_cvarEnabled) != 1) return;

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_alive(i)) continue;
        if (is_user_bot(i))    continue;
        if (g_defibs[i] <= 0)  continue;

        // Channel 4 - separate from the [E] prompt on channel 3.
        set_hudmessage(0, 200, 0, 0.02, 0.85, 0, 0.0, 1.1, 0.0, 0.0, 4);
        show_hudmessage(i, "Defib: %d", g_defibs[i]);
    }
}
