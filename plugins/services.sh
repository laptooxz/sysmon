register_plugin services

plugin_services_init() {
    write_state "services.known" ""
}

plugin_services_check() {
    [ -z "$WATCH_SERVICES" ] && return 0
    current=""
    for svc in $WATCH_SERVICES; do
        status=$(rc-service "$svc" status 2>/dev/null) || status="stopped"
        state="stopped"
        case "$status" in *started*) state="started" ;; *stopped*) state="stopped" ;; *crashed*) state="crashed" ;; *inactive*) state="inactive" ;; esac
        current="${current}${svc}:${state} "
    done
    saved=$(read_state services.known)
    [ -n "$saved" ] && [ "$saved" != "$current" ] && \
    for entry in $saved; do
        old_svc="${entry%:*}"
        old_state="${entry#*:}"
        new_state=""
        for ce in $current; do
            case "$ce" in "$old_svc":*) new_state="${ce#*:}"; break ;; esac
        done
        [ -z "$new_state" ] && new_state="stopped"
        [ "$old_state" != "$new_state" ] && \
        case "$new_state" in
            started)  notify "Service: $old_svc" "Started" 2 "device-added.oga" ;;
            stopped)  notify "Service: $old_svc" "Stopped" 3 "device-removed.oga" ;;
            crashed)  notify "Service: $old_svc" "Crashed!" 5 "dialog-error.oga" ;;
            inactive) notify "Service: $old_svc" "Inactive" 3 "dialog-warning.oga" ;;
        esac
    done
    write_state services.known "$current"
}
