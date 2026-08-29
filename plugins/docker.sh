register_plugin docker

plugin_docker_init() {
    write_state "docker.known" ""
}

plugin_docker_check() {
    current=""
    docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | \
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        name="${line%% *}"
        status="${line#* }"
        simple="up"
        case "$status" in
            Up*) simple="up" ;;
            Exited*) simple="exited" ;;
            Restarting*) simple="restarting" ;;
            Paused*) simple="paused" ;;
            Dead*) simple="dead" ;;
            Created*) simple="created" ;;
            *) simple="unknown" ;;
        esac
        current="${current}${name}:${simple} "
    done

    # Capture current from subshell
    current=$(docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | \
    awk '{
        name=$1; st=$2; s="up"
        if (st ~ /^Exited/) s="exited"
        else if (st ~ /^Restarting/) s="restarting"
        else if (st ~ /^Paused/) s="paused"
        else if (st ~ /^Dead/) s="dead"
        else if (st ~ /^Created/) s="created"
        else if (st ~ /^Up/) s="up"
        else s="unknown"
        printf "%s:%s ", name, s
    }' 2>/dev/null)

    saved=$(read_state docker.known)
    [ -n "$saved" ] && [ "$saved" != "$current" ] && \
    for entry in $saved; do
        old_name="${entry%:*}"
        old_status="${entry#*:}"
        new_status=""
        for ce in $current; do
            case "$ce" in "$old_name":*) new_status="${ce#*:}"; break ;; esac
        done
        [ -z "$new_status" ] && new_status="exited"
        [ "$old_status" != "$new_status" ] && \
        case "$new_status" in
            up)         notify "Docker: $old_name" "Container started" 2 "device-added.oga" ;;
            exited)     notify "Docker: $old_name" "Exited" 4 "dialog-warning.oga" ;;
            restarting) notify "Docker: $old_name" "Restarting!" 5 "dialog-error.oga" ;;
            paused)     notify "Docker: $old_name" "Paused" 3 "dialog-warning.oga" ;;
            dead)       notify "Docker: $old_name" "DEAD" 5 "dialog-error.oga" ;;
        esac
    done
    write_state docker.known "$current"
}
