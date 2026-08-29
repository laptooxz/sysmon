register_plugin resources

plugin_resources_init() {
    write_state "resources.disk" "ok"
    write_state "resources.mem" "ok"
    write_state "resources.load" "ok"
}

plugin_resources_check() {
    # --- Disk ---
    disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    [ -z "$disk_usage" ] && disk_usage=0
    disk_state=$(read_state resources.disk)
    if [ "$disk_usage" -ge "$DISK_CRIT" ] && [ "$disk_state" != "crit" ]; then
        notify "Disk Critical" "/ is ${disk_usage}% full" 5 "dialog-error.oga"
        write_state resources.disk "crit"
    elif [ "$disk_usage" -ge "$DISK_WARN" ] && [ "$disk_state" != "warn" ] && [ "$disk_state" != "crit" ]; then
        notify "Disk Warning" "/ is ${disk_usage}% full" 4 "dialog-warning.oga"
        write_state resources.disk "warn"
    elif [ "$disk_usage" -lt "$DISK_WARN" ] && { [ "$disk_state" = "warn" ] || [ "$disk_state" = "crit" ]; }; then
        notify "Disk OK" "/ is ${disk_usage}% full" 1 "complete.oga"
        write_state resources.disk "ok"
    fi

    # --- Memory ---
    mem_total=$(free 2>/dev/null | awk '/Mem:/{print $2}')
    mem_avail=$(free 2>/dev/null | awk '/Mem:/{print $7}')
    [ -z "$mem_total" ] && mem_total=1
    [ -z "$mem_avail" ] && mem_avail=0
    mem_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
    mem_state=$(read_state resources.mem)
    if [ "$mem_pct" -ge "$MEM_CRIT" ] && [ "$mem_state" != "crit" ]; then
        notify "Memory Critical" "${mem_pct}% used" 5 "dialog-error.oga"
        write_state resources.mem "crit"
    elif [ "$mem_pct" -ge "$MEM_WARN" ] && [ "$mem_state" != "warn" ] && [ "$mem_state" != "crit" ]; then
        notify "Memory Warning" "${mem_pct}% used" 4 "dialog-warning.oga"
        write_state resources.mem "warn"
    elif [ "$mem_pct" -lt "$MEM_WARN" ] && { [ "$mem_state" = "warn" ] || [ "$mem_state" = "crit" ]; }; then
        notify "Memory OK" "${mem_pct}% used" 1 "complete.oga"
        write_state resources.mem "ok"
    fi

    # --- Load ---
    load_1=$(uptime | sed 's/.*load average[s]*: *//' | cut -d, -f1 | tr -d ' ')
    [ -z "$load_1" ] && load_1="0"
    load_int=$(echo "$load_1" | awk '{print int($1+0.5)}')
    [ -z "$load_int" ] && load_int=0
    load_state=$(read_state resources.load)
    if [ "$load_int" -ge "$LOAD_CRIT" ] && [ "$load_state" != "crit" ]; then
        notify "Load Critical" "Load: $load_1" 5 "dialog-error.oga"
        write_state resources.load "crit"
    elif [ "$load_int" -ge "$LOAD_WARN" ] && [ "$load_state" != "warn" ] && [ "$load_state" != "crit" ]; then
        notify "Load Warning" "Load: $load_1" 4 "dialog-warning.oga"
        write_state resources.load "warn"
    elif [ "$load_int" -lt "$LOAD_WARN" ] && { [ "$load_state" = "warn" ] || [ "$load_state" = "crit" ]; }; then
        notify "Load OK" "Load: $load_1" 1 "complete.oga"
        write_state resources.load "ok"
    fi
}
