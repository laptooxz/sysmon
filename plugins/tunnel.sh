register_plugin tunnel

plugin_tunnel_init() {
    write_state "tunnel.known" ""
}

_state_status() {
    # given an entry "name:status:port", print the status field
    rest="${1#*:}"
    printf '%s' "${rest%%:*}"
}

plugin_tunnel_check() {
    [ -z "$WATCH_ENDPOINTS" ] && return 0
    current=""
    for ep in $WATCH_ENDPOINTS; do
        port="${ep%%:*}"
        name="${ep#*:}"
        status="up"
        code=$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "http://127.0.0.1:$port/" 2>/dev/null) || status="down"
        [ "$code" = "000" ] && status="down"
        current="${current}${name}:${status}:${port} "
    done
    saved=$(read_state tunnel.known)
    [ -n "$saved" ] && [ "$saved" != "$current" ] && \
    for entry in $saved; do
        old_name="${entry%%:*}"
        rest="${entry#*:}"
        old_status="${rest%%:*}"
        new_status=""
        down_port=""
        for ce in $current; do
            case "$ce" in
                "${old_name}:up:"*)
                    new_status="up"
                    break ;;
                "${old_name}:down:"*)
                    new_status="down"
                    down_port="${ce##*:}"
                    break ;;
            esac
        done
        [ -z "$new_status" ] && new_status="down"
        if [ "$old_status" != "$new_status" ]; then
            case "$new_status" in
                up)   notify "Tunnel OK: $old_name" "Back online" 2 "complete.oga" ;;
                down) notify "Tunnel DOWN: $old_name" "Unreachable on :${down_port:-?}" 5 "dialog-error.oga" ;;
            esac
        fi
    done
    write_state tunnel.known "$current"
}
