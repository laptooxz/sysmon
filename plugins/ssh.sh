register_plugin ssh

AUTH_LOG="/var/log/messages"

plugin_ssh_init() {
    write_state "ssh.pos" "0"
}

plugin_ssh_check() {
    [ ! -f "$AUTH_LOG" ] && return 0
    pos_file="$STATE_DIR/ssh.pos"
    saved_size=$(cat "$pos_file" 2>/dev/null || echo 0)
    log_size=$(stat -c '%s' "$AUTH_LOG" 2>/dev/null || echo 0)
    [ "$log_size" -lt "$saved_size" ] && saved_size=0
    [ "$log_size" -le "$saved_size" ] && return 0

    tail -c +$((saved_size + 1)) "$AUTH_LOG" 2>/dev/null | \
    while IFS= read -r line; do
        case "$line" in *"sshd"*) ;; *) continue ;; esac

        case "$line" in *"Accepted"*)
            after_for="${line##* for }"
            user="${after_for%% from *}"
            after_from="${line##* from }"
            ip="${after_from%% port *}"
            [ -z "$user" ] && continue
            known=false
            for net in $SSH_KNOWN_NETS; do
                if ip_in_net "$ip" "$net"; then known=true; break; fi
            done
            if [ "$known" = "true" ]; then
                dedup_check "ssh_${user}_${ip}" 60 && \
                    notify "SSH Login: $user" "Known IP: $ip" 2 "message-new-instant.oga"
            else
                dedup_check "ssh_unknown_${ip}" 300 && \
                    notify "SSH Login: $user" "UNKNOWN IP: $ip" 4 "dialog-warning.oga"
            fi
        esac

        case "$line" in *"Failed password"*)
            after_for="${line##*Failed password for }"
            user="${after_for%% from *}"
            case "$user" in "invalid user "*) user="${user#invalid user }" ;; esac
            after_from="${line##* from }"
            ip="${after_from%% port *}"
            [ -z "$user" ] && continue
            dedup_check "ssh_fail_${ip}" 120 && \
                notify "SSH Failed: $user" "From $ip" 3 "dialog-warning.oga"
        esac

        case "$line" in *"Disconnected from user"*)
            after="${line##*Disconnected from user }"
            user="${after%% from *}"
            after_from="${line##* from }"
            ip="${after_from%% port *}"
            [ -n "$user" ] && [ -n "$ip" ] && \
                dedup_check "ssh_out_${user}_${ip}" 60 && \
                notify "SSH Logout: $user" "From $ip" 1 "device-removed.oga"
        esac

        case "$line" in *"Received disconnect"*)
            ip=$(echo "$line" | sed -n 's/.* from \([^ ]*\):.*/\1/p')
            [ -n "$ip" ] && \
                dedup_check "ssh_disc_${ip}" 60 && \
                notify "SSH Disconnect" "From $ip" 1 "device-removed.oga"
        esac
    done
    echo "$log_size" > "$pos_file"
}
