register_plugin commands

CMD_LOG="/var/log/sysmon_cmds.log"

plugin_commands_init() {
    write_state "commands.pos" "$(stat -c '%s' "$CMD_LOG" 2>/dev/null || echo 0)"
}

plugin_commands_check() {
    [ ! -f "$CMD_LOG" ] && return 0
    pos_file="$STATE_DIR/commands.pos"
    saved_size=$(cat "$pos_file" 2>/dev/null || echo 0)
    log_size=$(stat -c '%s' "$CMD_LOG" 2>/dev/null || echo 0)
    [ "$log_size" -lt "$saved_size" ] && saved_size=0
    [ "$log_size" -le "$saved_size" ] && return 0

    tail -c +$((saved_size + 1)) "$CMD_LOG" 2>/dev/null | \
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        tty=$(echo "$line" | sed -n 's/.*"tty":"\([^"]*\)".*/\1/p')
        cmd=$(echo "$line" | sed -n 's/.*"cmd":"\([^"]*\)".*/\1/p')
        ssh=$(echo "$line" | sed -n 's/.*"ssh":"\([^"]*\)".*/\1/p')
        user=$(echo "$line" | sed -n 's/.*"user":"\([^"]*\)".*/\1/p')
        cwd=$(echo "$line" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
        log_event "info" "Cmd" "$cmd ($cwd)"
    done
    echo "$log_size" > "$pos_file"
}
