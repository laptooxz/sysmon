register_plugin system

plugin_system_init() {
    write_state "system.heartbeat" "0"
}

plugin_system_check() {
    last_hb=$(read_state system.heartbeat)
    [ -z "$last_hb" ] && last_hb=0
    now=$(date +%s)
    elapsed=$((now - last_hb))
    if [ "$elapsed" -ge 1800 ]; then
        up=$(uptime -p 2>/dev/null | sed 's/^up //')
        load=$(uptime | sed 's/.*load average[s]*: *//')
        log_event "info" "Heartbeat" "Up $up — load: $load"
        write_state system.heartbeat "$now"
    fi
}
