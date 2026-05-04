// Forces a bot from the joining team to disconnect when a human picks T or CT.
//
// `bot_quota_mode fill` (server.cfg) caps total players at bot_quota by removing
// bots when humans join, but ReGameDLL picks the bot from the team with the
// MOST bots - not necessarily the team the human just joined. The result: a
// human joins T while CT loses a bot, and T ends up over-staffed compared to
// CT.
//
// This plugin watches TeamInfo and, after a human picks an active team, kicks
// a bot from that same team only if the team is now over-balanced (joining
// team has more total players than the other side). If the engine already
// handled the kick correctly the totals are even and we no-op.

#include <amxmodx>
#include <cstrike>

#define TASK_BOT_KICK 5000

new g_lastTeam[33];

public plugin_init()
{
    register_plugin("Bot Auto Replace", "1.0", "aiteklabs");
    register_event("TeamInfo", "OnTeamInfo", "a");
}

public client_putinserver(id)
{
    g_lastTeam[id] = 0;
}

public client_disconnected(id)
{
    g_lastTeam[id] = 0;
    remove_task(id + TASK_BOT_KICK);
}

public OnTeamInfo()
{
    new id = read_data(1);
    if (id < 1 || id > 32) return;
    if (!is_user_connected(id)) return;
    if (is_user_bot(id)) return;

    new team[12];
    read_data(2, team, charsmax(team));

    new new_team = team_int(team);
    new old_team = g_lastTeam[id];
    g_lastTeam[id] = new_team;

    if ((new_team == 1 || new_team == 2) && new_team != old_team)
    {
        // Wait for the engine's bot_quota_mode fill to react first; we only
        // intervene if the team distribution is still uneven after that.
        set_task(0.7, "task_kick_team_bot", id + TASK_BOT_KICK);
    }
}

public task_kick_team_bot(taskid)
{
    new id = taskid - TASK_BOT_KICK;

    if (!is_user_connected(id) || is_user_bot(id)) return;

    new CsTeams:cur = cs_get_user_team(id);
    if (cur != CS_TEAM_T && cur != CS_TEAM_CT) return;

    new total_t = 0, total_ct = 0;
    new first_bot_on_team = 0;

    for (new i = 1; i <= 32; i++)
    {
        if (!is_user_connected(i)) continue;
        new CsTeams:t = cs_get_user_team(i);
        if (t == CS_TEAM_T)       total_t++;
        else if (t == CS_TEAM_CT) total_ct++;

        if (is_user_bot(i) && t == cur && first_bot_on_team == 0)
            first_bot_on_team = i;
    }

    new joining_total = (cur == CS_TEAM_T) ? total_t  : total_ct;
    new other_total   = (cur == CS_TEAM_T) ? total_ct : total_t;

    // Engine already balanced or under-staffed the joining team - leave it.
    if (joining_total <= other_total) return;
    if (first_bot_on_team == 0) return;

    new bname[32];
    get_user_name(first_bot_on_team, bname, charsmax(bname));
    server_cmd("kick #%d", get_user_userid(first_bot_on_team));
    log_amx("[AUTOBOT] kicked %s from %s - human replacement", bname, (cur == CS_TEAM_T) ? "T" : "CT");
}

team_int(const team[])
{
    if (equal(team, "TERRORIST")) return 1;
    if (equal(team, "CT"))        return 2;
    return 0;
}
