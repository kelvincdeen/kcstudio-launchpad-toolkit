#!/bin/bash

#
# === KCStudio.nl Server Maintenance & Utility Script v1.2 ===
#


set -euo pipefail
IFS=$'\n\t'

# --- Helper Functions (MUST be at the top) ---
log() { echo -e "\n\e[32m[+]\e[0m $1"; }
warn() { echo -e "\n\e[33m[!]\e[0m $1"; }
log_err() { echo -e "\n\e[31m[!] \e[31m$1\e[0m"; }
err() { log_err "$1" >&2; exit 1; }
prompt() { read -rp "$(echo -e "\e[36m[?]\e[0m $1 ")" "$2"; }
pause() { echo ""; read -rp "Press [Enter] to continue..."; }
log_ok() { echo -e "  \e[32m✔\e[0m $1"; }

# --- Global Variables & Setup ---
REPORTS_DIR="/var/www/kcstudio/reports"
DOWNLOADS_DIR="/var/www/kcstudio/downloads"
sudo mkdir -p "$REPORTS_DIR"
sudo mkdir -p "$DOWNLOADS_DIR"
sudo chown "$(whoami):$(whoami)" "$DOWNLOADS_DIR" # Give current user ownership
sudo chmod 755 "$REPORTS_DIR"
sudo chmod 775 "$DOWNLOADS_DIR"

# --- Dependency Check Function ---
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        warn "'$1' command not found. This feature requires it."
        prompt "Would you like to try and install it now? (y/N)" choice
        if [[ "$choice" == [yY] ]]; then
            sudo apt-get update && sudo apt-get install -y "$1"
        else
            return 1
        fi
    fi
    return 0
}

# --- Menu Display Functions ---
show_logo() {
    clear
    echo -e '\033[1;37m'
    cat << 'EOF'
██╗  ██╗ ██████╗███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗    ███╗   ██╗██╗
██║ ██╔╝██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗   ████╗  ██║██║
█████╔╝ ██║     ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║   ██╔██╗ ██║██║
██╔═██╗ ██║     ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║   ██║╚██╗██║██║
██║  ██╗╚██████╗███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝██╗██║ ╚████║███████╗
╚═╝  ╚═╝ ╚═════╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝
EOF
    echo -e "\e[0m"
}

# --- Health & Status Functions ---
health_overview() {
    log "System Resource Overview"
    echo "--- Load Average (1, 5, 15 minutes) ---"
    echo "This number should ideally be below the number of CPU cores on your server."
    uptime | awk -F'load average:' '{ print $2 }' | sed 's/^[ \t]*//'
    echo -e "\n--- Memory Usage ---"
    free -h
    echo -e "\n--- Filesystem Usage ---"
    df -h /
}

health_htop() {
    log "Launching Interactive Process Viewer (htop)"
    if ! check_dep "htop"; then return; fi
    echo "Press 'q' or F10 to quit htop and return to the menu."
    # No pause needed here, htop is interactive.
    sudo htop
}

health_ncdu() {
    log "Launching Interactive Disk Usage Analyzer (ncdu)"
    if ! check_dep "ncdu"; then return; fi

    local scan_path
    prompt "Enter the directory to analyze [default: /]: " scan_path
    scan_path=${scan_path:-/}

    if [ ! -d "$scan_path" ]; then
        log_err "Directory '$scan_path' not found."
        return
    fi

    warn "Starting scan of '$scan_path'. This might take a while..."
    echo "Use arrow keys to navigate. Press 'q' to quit ncdu."
    echo ""
    read -rp "Press [Enter] to continue..."

    sudo ncdu "$scan_path"
}

health_top_procs() {
    log "Top 10 Processes by CPU Usage"
    ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 11
    log "Top 10 Processes by Memory Usage"
    ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%mem | head -n 11
}

health_disk_usage() {
    log "Analyzing Disk Usage of Top-Level Directories in / (Static)"
    warn "This may take a moment..."
    sudo du -h / --max-depth=1 2>/dev/null | sort -rh | head -n 20
}

health_net_listeners() {
    log "Active Network Listeners (TCP/UDP)"
    if ! check_dep "ss"; then return; fi
    sudo ss -tulnp
}

health_ssh_log() {
    log "Viewing Last 50 SSHD Authentication Log Entries"
    echo "Log file: /var/log/auth.log"
    echo "----------------------------------------------------------------------"
    if sudo test -f /var/log/auth.log; then
        sudo grep -a -i 'sshd' /var/log/auth.log | tail -n 50
    else
        warn "/var/log/auth.log not found or no sshd entries."
    fi
    echo "----------------------------------------------------------------------"
}

health_ufw_log() {
    log "Viewing Last 50 UFW Firewall Log Entries"
    local log_file="/var/log/ufw.log"
    echo "Log file: $log_file"
    echo "----------------------------------------------------------------------"
    if sudo test -f "$log_file"; then
        if [ ! -s "$log_file" ]; then
            warn "Log file is empty. UFW logging might be off. Enable with: sudo ufw logging on"
        else
            sudo tail -n 50 "$log_file"
        fi
    else
        warn "Log file not found. UFW logging might be off. Enable with: sudo ufw logging on"
    fi
    echo "----------------------------------------------------------------------"
}

health_sudo_history() {
    log "Recent 'sudo' Command History from Auth Logs"
    sudo grep 'sudo:' /var/log/auth.log | tail -n 20 || echo "No recent sudo activity found."
}

health_scan_project_logs() {
    log "Scanning All Project Logs for Recent Errors/Warnings"

    read -rp "How many lines of output would you like per log file? [default: 15]: " max_lines
    max_lines=${max_lines:-15}

    local found_errors=false

    sudo find /var/www -maxdepth 2 -type f -name "project.conf" | while read -r conf_file; do
        local project_path
        project_path=$(dirname "$conf_file")
        local project_name
        project_name=$(basename "$project_path")
        
        echo -e "\n\e[1;34m========== Project: $project_name ==========\e[0m"
        echo -e "Path: \e[90m$project_path\e[0m"

        if [ ! -d "$project_path/logs" ]; then
            echo "(No logs directory found)"
            continue
        fi

        for component_log_dir in "$project_path"/logs/*; do
            [ -d "$component_log_dir" ] || continue
            local component
            component=$(basename "$component_log_dir")

            echo -e "\n\e[1;33m--- Component: $component ---\e[0m"

            shopt -s nullglob
            local log_files=(
                "$component_log_dir"/output.log
                "$component_log_dir"/output.log.1
            )

            if [ ${#log_files[@]} -eq 0 ]; then
                echo "(No output.log or output.log.1 files found)"
                continue
            fi

            for log_file in "${log_files[@]}"; do
                echo -e "\n\e[90mFile: $(basename "$log_file")\e[0m"
                if sudo grep -q -i -E "error|warning|failed|exception|traceback|unhandled|critical|panic|fatal|segfault|locked" "$log_file" 2>/dev/null; then
                    sudo grep --color=always -i -C 2 -E "error|warning|failed|exception|traceback|unhandled|critical|panic|fatal|segfault|locked" "$log_file" 2>/dev/null | tail -n "$max_lines"
                    found_errors=true
                else
                    echo "(No errors found.)"
                fi
            done
        done
    done

    if ! $found_errors; then
        log_ok "Scan complete."
    fi
}


health_lynis() {
    log "Re-running Lynis Security Audit"
    warn "This may take several minutes..."
    if ! check_dep "lynis"; then return; fi
    local report_file="$REPORTS_DIR/lynis-report_$(date +%Y%m%d).txt"
    sudo lynis audit system --quiet --no-colors > "$report_file"
    sudo chmod 644 "$report_file" # Make readable by non-root
    log_ok "Lynis audit complete. Full report saved to $report_file"
    warn "Review important suggestions from Lynis:"
    grep -E "Suggestion|Warning" "$report_file" | cut -c 2- || echo "  No high-priority suggestions or warnings found."
}


# --- Utility Functions ---
util_manage_systemd() {
    if ! check_dep "fzf"; then return; fi
    log "Interactive Systemd Service Manager"

    local service_list
    service_list=$(systemctl list-units --type=service --all --no-pager --plain | \
                   sed -E 's/( loaded +active +running.*)/\x1b[32m\1\x1b[0m/' | \
                   sed -E 's/( loaded +inactive +dead.*)/\x1b[90m\1\x1b[0m/' | \
                   sed -E 's/( loaded +failed.*)/\x1b[31m\1\x1b[0m/')

    local service_name
    service_name=$(echo -e "$service_list" | \
                   fzf --ansi --prompt="Search for a service > " \
                       --header="[ENTER] to select, [CTRL-C] to cancel" \
                       --preview="systemctl status {1}" --preview-window=right:60%:wrap | awk '{print $1}')

    if [ -n "$service_name" ]; then
        log "Selected service: $service_name"
        sudo systemctl status "$service_name" --no-pager
        echo ""
        prompt "Action: (st)atus, (r)estart, (s)top, (e)nable, (d)isable, (l)ogs? " action
        case $action in
            st) sudo systemctl status "$service_name" --no-pager ;;
            r) sudo systemctl restart "$service_name" && log_ok "Service restarted." ;;
            s) sudo systemctl stop "$service_name" && log_ok "Service stopped." ;;
            e) sudo systemctl enable "$service_name" && log_ok "Service enabled." ;;
            d) sudo systemctl disable "$service_name" && log_ok "Service disabled." ;;
            l) log "Showing logs for $service_name. Press Ctrl+C to exit."; sudo journalctl -fu "$service_name" ;;
            *) warn "Invalid action." ;;
        esac
    else
        echo "No service selected."
    fi
}

util_manage_cron() {
    log "Manage User Cron Jobs"

    local users_with_crons
    users_with_crons=$(sudo find /var/spool/cron/crontabs -type f -printf "%f\n" 2>/dev/null || true)
    echo "Users with existing crontabs:"
    if [ -n "$users_with_crons" ]; then echo "$users_with_crons"; else echo "None"; fi
    echo "---"

    echo "1) Edit a user's crontab manually (with nano)"
    echo "2) Add a new simple cron job (wizard)"
    prompt "Your choice: " cron_choice

    if [[ "$cron_choice" == "1" ]]; then
        prompt "Enter the username whose crontab you want to edit: " cron_user
        if ! id "$cron_user" &>/dev/null; then log_err "User '$cron_user' does not exist."; return; fi
        export EDITOR=nano
        sudo crontab -u "$cron_user" -e
    elif [[ "$cron_choice" == "2" ]]; then
        prompt "Enter username to run the job as (e.g., root, www-data): " cron_user
        prompt "Enter the full command to run: " cron_command
        echo "How often should it run?"
        echo "  1) Hourly (@hourly)"
        echo "  2) Daily (@daily)"
        echo "  3) Weekly (@weekly)"
        echo "  4) Monthly (@monthly)"
        echo "  5) On Reboot (@reboot)"
        prompt "Choose frequency [1-5]: " freq_choice
        local schedule=""
        case $freq_choice in
            1) schedule="@hourly" ;;
            2) schedule="@daily" ;;
            3) schedule="@weekly" ;;
            4) schedule="@monthly" ;;
            5) schedule="@reboot" ;;
            *) log_err "Invalid frequency."; return;;
        esac
        local current_crontab
        current_crontab=$(sudo crontab -u "$cron_user" -l 2>/dev/null || true)
        printf "%s\n%s %s\n" "$current_crontab" "$schedule" "$cron_command" | sudo crontab -u "$cron_user" -
        log_ok "Cron job added for user '$cron_user'."
    else
        warn "Invalid choice."
    fi
}

util_manage_ssl() {
    log "Manage SSL Certificates (Certbot)"
    echo "1) List all current certificates"
    echo "2) Test renewal process for all certificates (Dry Run)"
    prompt "Your choice: " cert_choice
    case $cert_choice in
        1) sudo certbot certificates ;;
        2) sudo certbot renew --dry-run ;;
        *) warn "Invalid choice." ;;
    esac
}

util_litecli() {
    log "Interactive Database Explorer (litecli)"
    if ! check_dep "litecli"; then return; fi
    if ! check_dep "fzf"; then return; fi

    log "Searching for database files in /var/www..."
    local db_files
    db_files=$(sudo find /var/www -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \))

    if [ -z "$db_files" ]; then
        warn "No database files (.db, .sqlite, .sqlite3) found in /var/www."
        return
    fi

    local selected_db
    selected_db=$(echo "$db_files" | fzf --prompt="Select a database to explore > " --height=40% --border)

    if [ -z "$selected_db" ]; then
        echo "No database selected."
        return
    fi

    log "Selected database: $selected_db"

    echo
    printf "\e[33m%s\e[0m\n" "--- HOW TO USE LITECLI ---"
    printf " You are about to enter an interactive SQL client for SQLite.\n"
    printf "\n\e[36m%s\e[0m\n" "ESSENTIAL COMMANDS (start with a dot '.'):"
    printf "  - \e[32m.tables\e[0m          List all tables in the database.\n"
    printf "  - \e[32m.schema <table_name>\e[0m Show the structure of a specific table.\n"
    printf "  - \e[32mquit or \\q\e[0m      \e[31mExit the client and return to this script.\e[0m\n"
    printf "\n\e[36m%s\e[0m\n" "EXAMPLE SQL QUERIES (end with a semicolon ';'):"
    printf "  - \e[32mSELECT * FROM users LIMIT 10;\e[0m\n"
    printf "  - \e[32mSELECT count(*) FROM items;\e[0m\n"
    printf "\n\e[33m%s\e[0m\n" "TIPS:"
    printf "  - Use the \e[36mTab\e[0m key for smart auto-completion of commands and table/column names.\n"
    printf "  - Use \e[36mUp/Down\e[0m arrow keys to navigate command history.\n"

    echo ""
    read -rp "Press [Enter] to launch litecli..."

    # Launching with sudo to ensure permissions are correct
    sudo litecli "$selected_db"
}

util_download_url() {
    log "Download Files from URL"
    if ! check_dep "wget"; then return; fi
    if ! check_dep "tree"; then return; fi
    if ! check_dep "unzip"; then return; fi
    if ! check_dep "tar"; then return; fi

    log "💡 Tip: Uploading Files to Your Server"
    printf "\n\e[33m%s\e[0m\n" "Need to transfer a zip or file from your local machine?"
    printf " You can use temporary file-sharing services like:\n"
    printf "  - \e[36mhttps://file.io\e[0m\n"
    printf "  - \e[36mhttps://tmpfiles.org\e[0m\n"
    printf "\nUpload your file and paste the download URL into this tool when prompted.\n"
    printf "The script will handle the download and extraction automatically.\n"
    pause

    local urls
    prompt "Enter one or more space-separated URLs to download: " urls
    if [ -z "$urls" ]; then
        warn "No URLs provided."
        return
    fi

    local subfolder
    prompt "Enter a name for the subfolder in '$DOWNLOADS_DIR' to store these files: " subfolder
    if [ -z "$subfolder" ]; then
        warn "No subfolder name provided."
        return
    fi

    local dest_dir="$DOWNLOADS_DIR/$subfolder"
    if [ -d "$dest_dir" ]; then
        warn "Directory '$dest_dir' already exists. Files may be overwritten."
    else
        mkdir -p "$dest_dir"
        log_ok "Created directory '$dest_dir'"
    fi

    log "Starting downloads..."
    for url in $urls; do
        echo "--> Downloading $url"
        wget -P "$dest_dir" "$url"
    done

    log_ok "All downloads complete."
    log "Checking for archives to extract..."

    for file in "$dest_dir"/*; do
        case "$file" in
            *.zip)
                log "Unzipping: $(basename "$file")"
                unzip -o "$file" -d "$dest_dir" && rm "$file"
                ;;
            *.tar.gz|*.tgz)
                log "Extracting tar.gz: $(basename "$file")"
                tar -xzf "$file" -C "$dest_dir" && rm "$file"
                ;;
            *.tar)
                log "Extracting tar: $(basename "$file")"
                tar -xf "$file" -C "$dest_dir" && rm "$file"
                ;;
            *)
                log "Normal file(s): $(basename "$file")"
                ;;
        esac
    done

    log "Displaying contents of download folder:"
    echo "----------------------------------------------------------------------"
    tree "$dest_dir"
    echo "----------------------------------------------------------------------"
    log "Files are located in '$dest_dir'"
}


util_find() {
    log "Find File Content or Filenames"
    prompt "Search for a (F)ilename or a piece of (T)ext inside files? " search_type

    local search_dir
    prompt "Enter directory to search in (e.g., /var/www or /etc): " search_dir
    if [ ! -d "$search_dir" ]; then log_err "Directory not found."; return; fi

    if [[ "$search_type" == [Ff] ]]; then
        prompt "Enter filename pattern to find (wildcards allowed, e.g., *.log): " filename
        log "Searching for filenames matching '$filename'..."
        sudo find "$search_dir" -name "$filename"

    elif [[ "$search_type" == [Tt] ]]; then
        prompt "Enter text to search for: " text
        read -rp "Enter directories to exclude (comma-separated, e.g., venv,node_modules): " exclude_dirs_str

        local exclude_args=()
        IFS=',' read -ra DIRS_TO_EXCLUDE <<< "$exclude_dirs_str"
        for dir in "${DIRS_TO_EXCLUDE[@]}"; do
            if [ -n "$dir" ]; then
                exclude_args+=("--exclude-dir=${dir}")
            fi
        done

        log "Searching for text '$text'..."
        echo "Excluding directories: ${exclude_dirs_str:-None}"
        sudo grep -rI --color=always "${exclude_args[@]}" "$text" "$search_dir" || log_ok "No matches found."
    else
        warn "Invalid choice."
    fi
}

util_swap() {
    log "Set / Change Swap File"
    if [ -n "$(swapon --show)" ]; then
        warn "A swap file of size $(free -h | grep Swap | awk '{print $2}') already exists."
        prompt "This will replace it. Are you sure? (y/N)" swap_confirm
        if [[ "$swap_confirm" != [yY] ]]; then echo "Operation cancelled."; return; fi
    fi
    prompt "Enter desired swap size (e.g., 1G, 2G, 4G): " swap_size
    sudo swapoff /swapfile &>/dev/null || true
    sudo rm -f /swapfile
    sudo fallocate -l "$swap_size" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    log_ok "Swap file of size $swap_size created and enabled."
    free -h
}

util_goaccess() {
    log "Analyze NGINX Access Logs with GoAccess"
    if ! check_dep "goaccess"; then return; fi
    local report_file="$REPORTS_DIR/nginx_report_$(date +%Y%m%d).html"
    warn "This may take a moment..."

    local temp_report
    temp_report=$(mktemp --suffix=.html)
    sudo goaccess /var/log/nginx/access.log -o "$temp_report" --log-format=COMBINED
    sudo mv "$temp_report" "$report_file"
    sudo chmod 644 "$report_file"

    log_ok "Interactive HTML report generated at: $report_file"
    echo "To view it, copy it to your local machine and open it in a browser."
    echo -e "Example scp command (run on your local machine):\n  \e[36mscp -P <SSH_PORT> $(whoami)@<SERVER_IP>:$report_file .\e[0m"
}

util_file_browser() {
    log "GUI File Browser (Midnight Commander)"
    if ! check_dep "mc"; then return; fi

    echo "You are about to launch Midnight Commander, a powerful visual file manager."
    printf "\n\e[33m%s\e[0m\n" "--- HOW IT WORKS ---"
    printf " The screen is split into two panes. Use the \e[36mTab\e[0m key to switch between them.\n"
    printf " This is useful for copying/moving files from one location to another.\n"
    printf "\n\e[33m%s\e[0m\n" "--- KEYBOARD SHORTCUTS ---"
    printf "  - \e[36mArrow Keys\e[0m:  Navigate up and down.\n"
    printf "  - \e[36mEnter\e[0m:       Enter a directory or execute a file.\n"
    printf "  - \e[36mMouse\e[0m:       You can also use your mouse to navigate!\n"
    printf "  - \e[32mF3 (View)\e[0m:   \e[90mSafely view the contents of a file (read-only).\e[0m\n"
    printf "  - \e[36mF4 (Edit)\e[0m:   \e[90mEdit a text file (uses 'nano').\e[0m\n"
    printf "  - \e[36mF5 (Copy)\e[0m:   \e[90mCopy the selected file(s) to the other pane.\e[0m\n"
    printf "  - \e[36mF6 (Move)\e[0m:   \e[90mMove the selected file(s) to the other pane.\e[0m\n"
    printf "  - \e[31mF8 (Delete)\e[0m: \e[90mDelete the selected file(s) (with confirmation).\e[0m\n"
    printf "  - \e[33mF10 (Quit)\e[0m:  \e[90mExit the file browser and return to the main menu.\e[0m\n"

    read -rp "Press [Enter] to continue..."

    # Launch with a modern dark skin
    sudo mc -S gotar
}


# --- Advanced Config Functions ---
adv_fail2ban() {
    log "Manage Fail2Ban"
    echo "1) List banned IPs (sshd jail)"
    echo "2) Unban an IP"
    prompt "Your choice: " f2b_choice
    case $f2b_choice in
        1) sudo fail2ban-client status sshd ;;
        2)
            prompt "Enter IP to unban: " ip_to_unban
            sudo fail2ban-client set sshd unbanip "$ip_to_unban"
            ;;
        *) warn "Invalid choice." ;;
    esac
}

adv_timezone() {
    log "Configuring System Timezone"
    echo "This will launch an interactive timezone selector."
    sudo dpkg-reconfigure tzdata
    log_ok "Timezone updated. Current time: $(date)"
}

adv_auditd() {
    log "(Opt-in) Advanced System Auditing (auditd)"
    warn "This will install 'auditd' and generate a large volume of detailed system logs."
    warn "This is recommended for advanced security analysis or compliance requirements only."
    prompt "Are you sure you want to install and enable auditd? (y/N)" audit_confirm
    if [[ "$audit_confirm" == [yY] ]]; then
        sudo apt-get update && sudo apt-get install -y auditd audispd-plugins
        sudo systemctl enable --now auditd
        log_ok "auditd has been installed and enabled."
    else
        echo "Installation cancelled."
    fi
}

# --- Sub-Menu Functions ---
show_health_menu() {
    while true; do
        show_logo
        echo "==================================================================================="
        echo "        Server Health & Status"
        echo "==================================================================================="
        echo ""
        echo "  1) System Resource Overview"
        echo "  2) Interactive Process Viewer (htop)"
        echo "  3) Interactive Disk Usage Analyzer (ncdu)"
        echo "  4) List Top Processes (Static)"
        echo "  5) Analyze Disk Usage (Static)"
        echo "  6) List Active Network Listeners"
        echo "  7) View SSH Authentication Log"
        echo "  8) View Firewall (UFW) Log"
        echo "  9) Check sudo Command History"
        echo "  10) Scan Project Logs for Errors"
        echo "  11) Re-run Lynis Security Audit"
        echo ""
        echo "  M) Return to Main Menu"
        echo ""
        echo "==================================================================================="
        prompt "Enter choice: " choice

        case $choice in
            1) health_overview; pause ;;
            2) health_htop ;;
            3) health_ncdu ;;
            4) health_top_procs; pause ;;
            5) health_disk_usage; pause ;;
            6) health_net_listeners; pause ;;
            7) health_ssh_log; pause ;;
            8) health_ufw_log; pause ;;
            9) health_sudo_history; pause ;;
            10) health_scan_project_logs; pause ;;
            11) health_lynis; pause ;;
            [Mm]) return 0 ;;
            *) warn "Invalid choice."; pause ;;
        esac
    done
}

show_utilities_menu() {
    while true; do
        show_logo
        echo "==================================================================================="
        echo "             Server Utilities"
        echo "==================================================================================="
        echo "  1) Manage a Systemd Service (Interactive)"
        echo "  2) Manage User Cron Jobs"
        echo "  3) Manage SSL Certificates (Certbot)"
        echo "  4) Explore Databases (litecli)"
        echo "  5) Download Files from URL"
        echo "  6) Find File or Text"
        echo "  7) Set / Change Swap File"
        echo "  8) Analyze NGINX Logs (GoAccess)"
        echo "  9) Open a GUI File Browser (mc)"
        echo ""
        echo "  M) Return to Main Menu"
        echo "==================================================================================="
        prompt "Enter choice: " choice

        case $choice in
            1) util_manage_systemd; pause ;;
            2) util_manage_cron; pause ;;
            3) util_manage_ssl; pause ;;
            4) util_litecli ;;
            5) util_download_url; pause ;;
            6) util_find; pause ;;
            7) util_swap; pause ;;
            8) util_goaccess; pause ;;
            9) util_file_browser ;;
            [Mm]) return 0 ;;
            *) warn "Invalid choice."; pause ;;
        esac
    done
}

show_advanced_menu() {
    while true; do
        show_logo
        echo "==================================================================================="
        echo "          Advanced Configuration"
        echo "==================================================================================="
        echo
        echo "  1) Manage Fail2Ban (Show/Unban IP)"
        echo "  2) Configure System Timezone"
        echo "  3) (Opt-in) Install Advanced Auditing (auditd)"
        echo "  M) Return to Main Menu"
        echo
        echo "==================================================================================="
        prompt "Enter choice: " choice

        case $choice in
            1) adv_fail2ban; pause ;;
            2) adv_timezone; pause ;;
            3) adv_auditd; pause ;;
            [Mm]) return 0 ;;
            *) warn "Invalid choice."; pause ;;
        esac
    done
}

show_help() {
    show_logo
    log "Server Maintenance & Utility Help"
    printf "\nThis script is your server's command center, divided into three parts:"

    printf "\n\n\e[36m%s\e[0m\n" "1. Server Health & Status"
    printf "   %s\n" "This section is for diagnostics. It helps you answer 'What's happening right now?'."
    printf "   - \e[33m%s\e[0m: %s\n" "htop" "An interactive, real-time process viewer. The best way to see CPU/RAM usage."
    printf "   - \e[33m%s\e[0m: %s\n" "ncdu" "An interactive disk usage analyzer. Easily find what's taking up space."
    printf "   - \e[33m%s\e[0m: %s\n" "Log Viewers" "Quickly check the latest SSH login attempts and firewall activity."

    printf "\n\e[36m%s\e[0m\n" "2. Server Utilities"
    printf "   %s\n" "This section contains 'easy buttons' for common administrative tasks."
    printf "   - \e[33m%s\e[0m: %s\n" "Explore Databases" "Finds all SQLite databases and lets you browse them with a friendly CLI."
    printf "   - \e[33m%s\e[0m: %s\n" "Download Files" "A simple wizard to download files from the web to your server."
    printf "   - \e[33m%s\e[0m: %s\n" "Manage Services" "An interactive, searchable list to start/stop/restart any service."
    printf "   - \e[33m%s\e[0m: %s\n" "File Browser" "A visual, two-pane file manager for easy navigation and file operations."

    printf "\n\e[36m%s\e[0m\n" "3. Advanced Configuration"
    printf "   %s\n" "This section is for less-frequent, powerful configuration changes."
    printf "   - \e[33m%s\e[0m: %s\n" "Manage Fail2Ban" "View or unban IPs blocked by the intrusion prevention system."

    pause
}

# --- Main Menu Loop ---
while true; do
    show_logo
    echo "==================================================================================="
    echo "      Server Maintenance & Utility Toolkit - Main Menu"
    echo "==================================================================================="
    echo
    echo -e "  \e[36m1) Server Health & Status...\e[0m (CPU, RAM, Logs, Disk...)"
    echo -e "  \e[36m2) Server Utilities...\e[0m (Services, Cron, Databases, Files...)"
    echo -e "  \e[36m3) Advanced Configuration...\e[0m (Fail2Ban, Timezone...)"
    echo
    echo
    echo "  H) Help / About this Tool        Q) Quit"
    echo
    echo "==================================================================================="
    prompt "Enter choice: " main_choice

    case $main_choice in
        1) show_health_menu ;;
        2) show_utilities_menu ;;
        3) show_advanced_menu ;;
        [Hh]) show_help ;;
        [Qq]) echo "Exiting." && exit 0 ;;
        *) warn "Invalid choice." ; pause ;;
    esac
done