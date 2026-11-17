
#!/usr/bin/env bash

SCRIPT="$HOME/dev/scripts/autostart_rice.sh"

# Monitorstatus direkt aus dem Kernel auslesen
get_monitor_state() {
    local file

    for file in /sys/class/drm/card*-*/status; do
        [[ -f "$file" ]] || continue

        if [[ "$(<"$file")" == "connected" ]]; then
            echo "${file%/status}"
        fi
    done
}

# Ausgangszustand ermitteln
LAST_STATE="$(get_monitor_state)"

# Setup beim Start einmal laden
"$SCRIPT"

while sleep 3; do
    CURRENT_STATE="$(get_monitor_state)"

    if [[ "$CURRENT_STATE" != "$LAST_STATE" ]]; then

        # Kurz warten, bis die Verbindung stabil ist
        sleep 2
        CURRENT_STATE="$(get_monitor_state)"

        if [[ "$CURRENT_STATE" != "$LAST_STATE" ]]; then
            echo "Monitor configuration changed. Reloading..."

            "$SCRIPT"
            LAST_STATE="$CURRENT_STATE"
        fi
    fi
done
