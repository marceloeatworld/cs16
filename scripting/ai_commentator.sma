// Logs kills/headshots/round events to ai_events.txt and prints
// replies from ai_responses.txt in chat.
// The Python sidecar (ai_commentator.py) handles the Cloudflare
// Workers AI calls out of process.

#include <amxmodx>
#include <cstrike>

new g_eventsFile[128];
new g_responsesFile[128];

public plugin_init()
{
    register_plugin("AI Commentator", "1.0", "aiteklabs");

    get_localinfo("amxx_datadir", g_eventsFile, charsmax(g_eventsFile));
    copy(g_responsesFile, charsmax(g_responsesFile), g_eventsFile);
    add(g_eventsFile, charsmax(g_eventsFile), "/ai_events.txt");
    add(g_responsesFile, charsmax(g_responsesFile), "/ai_responses.txt");

    register_event("DeathMsg", "event_death", "a");
    register_logevent("event_round_start", 2, "1=Round_Start");
    register_logevent("event_round_end", 2, "1=Round_End");

    set_task(3.0, "task_check_responses", 0, "", 0, "b");
}

public event_death()
{
    new killer = read_data(1);
    new victim = read_data(2);
    new headshot = read_data(3);
    new weapon[32], killer_name[32], victim_name[32];

    read_data(4, weapon, charsmax(weapon));

    if (killer > 0 && killer != victim)
    {
        get_user_name(killer, killer_name, charsmax(killer_name));
        get_user_name(victim, victim_name, charsmax(victim_name));

        new line[256];
        if (headshot)
            formatex(line, charsmax(line), "HEADSHOT|%s|%s|%s", killer_name, victim_name, weapon);
        else
            formatex(line, charsmax(line), "KILL|%s|%s|%s", killer_name, victim_name, weapon);

        write_event(line);
    }
    return PLUGIN_CONTINUE;
}

public event_round_start()
{
    write_event("ROUND_START");
}

public event_round_end()
{
    write_event("ROUND_END");
}

write_event(const text[])
{
    new file = fopen(g_eventsFile, "a");
    if (file)
    {
        new timestamp[32];
        get_time("%H:%M:%S", timestamp, charsmax(timestamp));
        fprintf(file, "%s|%s^n", timestamp, text);
        fclose(file);
    }
}

public task_check_responses()
{
    if (!file_exists(g_responsesFile))
        return;

    new file = fopen(g_responsesFile, "r");
    if (!file)
        return;

    new line[256];
    new found = false;
    while (fgets(file, line, charsmax(line)))
    {
        trim(line);
        if (line[0] != 0)
        {
            client_print(0, print_chat, "[AI] %s", line);
            found = true;
        }
    }
    fclose(file);

    if (found)
    {
        new clear = fopen(g_responsesFile, "w");
        if (clear)
            fclose(clear);
    }
}
