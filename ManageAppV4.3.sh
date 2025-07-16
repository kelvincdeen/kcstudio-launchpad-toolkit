#!/bin/bash

# === KCStudio.nl ADVANCED PROJECT OPERATOR v4.3 ===
# The Definitive Project Management & Maintenance Toolkit
#

set -euo pipefail
IFS=$'\n\t'

# --- Helper Functions ---
log() { echo -e "\n[+] $1"; }
log_ok() { echo -e "  \e[32m✔\e[0m $1"; }
log_warn() { echo -e "  \e[33m!\e[0m $1"; }
log_err() { echo -e "\n[!] \e[31m$1\e[0m"; } # No exit, for non-fatal errors
err() { log_err "$1" >&2; exit 1; }

# --- Menu Display Functions ---
show_logo() {
    echo -e '\033[1;37m'
    cat << 'EOF'
██╗  ██╗ ██████╗███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗    ███╗   ██╗██╗
██║ ██╔╝██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗   ████╗  ██║██║
█████╔╝ ██║     ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║   ██╔██╗ ██║██║
██╔═██╗ ██║     ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║   ██║╚██╗██║██║
██║  ██╗╚██████╗███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝██╗██║ ╚████║███████╗
╚═╝  ╚═╝ ╚═════╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝
EOF
    echo -e "\e[0m" # Reset color
}

pause() {
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

check_dep() {
    if ! command -v "$1" &> /dev/null; then
        log_warn "'$1' command not found. This feature requires it."
        read -rp "Would you like to try and install it now? (y/N)" choice
        if [[ "$choice" == [yY] ]]; then
            sudo apt-get update && sudo apt-get install -y "$1"
        else
            return 1
        fi
    fi
    return 0
}


# --- Global & Project Variables ---
PROJECT_ROOT="/var/www"
BACKUP_ROOT="/var/backups"

# --- Startup Logic ---
list_all_domains() {
    log "Listing all managed projects and their domains..."
    echo "----------------------------------------------------------------------------------------------------"
    printf "%-30s | %-35s | %-35s\n" "PROJECT NAME" "FRONTEND DOMAIN" "API DOMAIN"
    echo "----------------------------------------------------------------------------------------------------"

    sudo find "$PROJECT_ROOT" -maxdepth 2 -type f -name "project.conf" | while read -r conf_file; do
        (
            # shellcheck source=/dev/null
            source <(sudo cat "$conf_file")
            printf "%-30s | %-35s | %-35s\n" "$PROJECT" "${FRONTEND_DOMAIN:-N/A}" "${API_DOMAIN:-N/A}"
        )
    done
    echo "----------------------------------------------------------------------------------------------------"
    pause
}

if [[ "${1-}" == "--list-all" ]]; then
    list_all_domains
    exit 0
fi

PROJECT_NAME_ARG="${1-}"

if [ -z "$PROJECT_NAME_ARG" ]; then
    clear
    show_logo

    log "Searching for available projects to manage..."
    AVAILABLE_PROJECTS=()
    while IFS= read -r -d $'\0' conf_file; do
        AVAILABLE_PROJECTS+=("$(basename "$(dirname "$conf_file")")")
    done < <(sudo find "$PROJECT_ROOT" -maxdepth 2 -type f -name "project.conf" -print0)

    if [ ${#AVAILABLE_PROJECTS[@]} -eq 0 ]; then
        err "No valid projects found in '$PROJECT_ROOT'."
    fi

    echo "Please select a project to manage (or 'A' to list all domains):"
select project in "${AVAILABLE_PROJECTS[@]}"; do
    if [[ "$REPLY" =~ ^[Aa]$ ]]; then
        list_all_domains
        continue
    elif [[ -n "$project" ]]; then
        PROJECT_NAME_ARG="$project"
        break
    else
        echo "Invalid selection."
    fi
done
fi

PROJECT_CONF_PATH="$PROJECT_ROOT/$PROJECT_NAME_ARG/project.conf"
[[ -f "$PROJECT_CONF_PATH" ]] || err "Project '$PROJECT_NAME_ARG' is not a valid project (missing 'project.conf')."

log "Loading manifest for project '$PROJECT_NAME_ARG'..."
source <(sudo cat "$PROJECT_CONF_PATH")
log_ok "Project manifest loaded successfully."

BACKEND_SERVICES=()
for comp in "${SELECTED_COMPONENTS[@]}"; do [[ "$comp" != "website" ]] && BACKEND_SERVICES+=("$comp"); done
APP_USER="app_$PROJECT"

# --- Menu and Action Functions ---

select_component() {
  local prompt_message="$1"
  local -n components_array=$2

  echo ""
  echo "$prompt_message"
  select comp in "${components_array[@]}"; do
    if [[ -n "$comp" ]]; then
      REPLY="$comp"
      return 0
    else
      echo "Invalid selection."
    fi
  done
}

# --- Core Functions ---
show_info() {
    log "Project Information for '$PROJECT'"
    echo "------------------------------------------"
    printf "  %-20s: %s\n" "Project Name" "$PROJECT"
    printf "  %-20s: %s\n" "Path" "$APP_PATH"
    if [[ "$HAS_WEBSITE" == "true" ]]; then
      printf "  %-20s: %s\n" "Frontend Domain" "https://$FRONTEND_DOMAIN"
    fi
    if [[ "$HAS_BACKEND" == "true" ]]; then
       printf "  %-20s: %s\n" "API Base URL" "https://$API_DOMAIN/v1/"
    fi
    echo ""
    printf "  %-20s: %s\n" "Installed Components" "${SELECTED_COMPONENTS[*]}"
    printf "  %-20s: %s\n" "Backend Services" "${BACKEND_SERVICES[*]:-None}"
    echo "------------------------------------------"
}

restart_component() {
  if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services to restart."; return; fi
  select_component "Which backend service do you want to restart?" BACKEND_SERVICES
  local comp="$REPLY"
  log "Restarting '$comp' service for project '$PROJECT'..."
  sudo systemctl restart "$PROJECT-$comp.service"
  log_ok "'$comp' service has been sent the restart command."
  sleep 1
  sudo systemctl status "$PROJECT-$comp.service" --no-pager --lines=5
}

view_logs() {
  if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then
    log_err "No backend services to view logs for."
    return
  fi

  echo ""
  echo "What would you like to do?"
  echo "1) View last 10 lines of each backend's logs"
  echo "2) Tail live logs for a specific backend"
  read -rp "Enter choice [1-2]: " log_choice

  case "$log_choice" in
    1)
      log "Showing last 10 lines of logs for all backend services:"
      for comp in "${BACKEND_SERVICES[@]}"; do
        echo "------------------ $comp ------------------"
        sudo tail -n 10 "$APP_PATH/logs/$comp/output.log" || log_warn "Could not read log for $comp"
        echo ""
      done
      ;;
    2)
      select_component "Which backend service's logs do you want to view (live)?" BACKEND_SERVICES
      local comp="$REPLY"
      log "Tailing logs for '$comp'. Press Ctrl+C to stop."
      sudo tail -f "$APP_PATH/logs/$comp/output.log"
      ;;
    *)
      log_warn "Invalid choice."
      ;;
  esac
}


check_health() {
  if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services to check."; return; fi
  log "Checking health of all available backend services for '$PROJECT'..."
  for comp in "${BACKEND_SERVICES[@]}"; do
    local port_var="PORT_${comp^^}"
    if [ -z "${!port_var-}" ]; then
        printf "  - %-10s => \e[31mPort not defined in manifest\e[0m\n" "$comp"
        continue
    fi
    local port="${!port_var}"

    printf "  - %-10s (Port %-5s) => Internal: " "$comp" "$port"
    if curl --fail -s -o /dev/null "http://127.0.0.1:$port/health"; then
      echo -e "\e[32mOK\e[0m"
    else
      echo -e "\e[31mFAILED\e[0m"
    fi

    local public_url="https://$API_DOMAIN/v1/$comp/health"
    printf "%26s => Full Stack: " ""
    if curl --fail -s -L -o /dev/null "$public_url"; then
      echo -e "\e[32mOK\e[0m"
    else
      echo -e "\e[31mFAILED\e[0m"
    fi
  done
}

status_all() {
  if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services to show status for."; return; fi
  log "Displaying systemd status for all project services..."
  for comp in "${BACKEND_SERVICES[@]}"; do
    echo "-------------------------------------"
    echo "Service: $PROJECT-$comp.service"
    echo "-------------------------------------"
    sudo systemctl status "$PROJECT-$comp.service" --no-pager
  done
}

reload_nginx() {
  log "Testing NGINX configuration..."
  if sudo nginx -t; then
    log_ok "Configuration is OK. Reloading NGINX..."
    sudo systemctl reload nginx
    log_ok "NGINX reloaded successfully."
  else
    log_err "NGINX configuration test failed. Not reloading."
  fi
}

reload_website() {
  if ! [[ "$HAS_WEBSITE" == "true" ]]; then
    log_err "No 'website' component found for this project."
    return
  fi
  local site_path="$APP_PATH/website"
  local web_user="web_$PROJECT"
  log "Reloading website files..."
  echo "This is useful after deploying new frontend files (e.g., via FTP, SCP, or Deploy from URL)."
  echo "It resets file ownership to the '$web_user' user and reloads NGINX."
  sudo chown -R "$web_user:$web_user" "$site_path"
  sudo chmod -R 755 "$site_path"
  reload_nginx
  log_ok "Website permissions reset and NGINX reloaded."
}

# --- Developer Experience Functions ---
show_admin_keys() {
    if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services to show keys for."; return; fi
    log "Displaying Admin API Keys"
    echo "These keys are for server-to-server or administrative tasks ONLY."
    echo "They should NEVER be used in a public frontend."
    echo "-----------------------------------------------------"
    for comp in "${BACKEND_SERVICES[@]}"; do
        local key
        key=$(sudo grep -E '^ADMIN_API_KEY=' "$APP_PATH/$comp/.env" | cut -d'=' -f2)
        printf "  - %-10s: %s\n" "$comp" "$key"
    done
    echo "-----------------------------------------------------"
}

rotate_jwt_secret() {
    if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services found to rotate JWT secret for."; return; fi

    log_err "SECURITY WARNING: JWT Secret Rotation"
    log_warn "This action will generate a new master key for signing all session tokens for project '$PROJECT'."
    log_warn "This will immediately invalidate ALL active user sessions, forcing everyone to log in again."
    echo ""
    read -rp "Are you absolutely sure you want to proceed? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Operation cancelled."
        return
    fi

    log "Step 1: Generating new secure JWT secret..."
    local NEW_JWT_SECRET
    NEW_JWT_SECRET=$(openssl rand -hex 32)
    log_ok "New secret generated."

    log "Step 2: Updating .env files for all backend services..."
    for comp in "${BACKEND_SERVICES[@]}"; do
        local env_file="$APP_PATH/$comp/.env"
        sudo sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$NEW_JWT_SECRET/" "$env_file"
        log_ok "Updated secret for '$comp' service."
    done

    log "Step 3: Restarting all backend services to apply the new secret..."
    for comp in "${BACKEND_SERVICES[@]}"; do
        sudo systemctl restart "$PROJECT-$comp.service"
        log_ok "Restarted '$comp' service."
    done

    log_ok "JWT secret rotation complete. All user sessions have been invalidated."
}


deploy_code_local() {
    local all_components=("${BACKEND_SERVICES[@]}")
    if [[ "$HAS_WEBSITE" == "true" ]]; then
        all_components+=("website")
    fi

    log "Deploy New Code from Local Path"
    echo "This tool safely deploys new code from a local directory into the selected component."
    echo ""
    echo "  - For \e[36mbackend apps\e[0m, it preserves your database files (*.db) and Python venv."
    echo "  - For \e[36mwebsites\e[0m, it mirrors the build folder exactly, removing outdated files."
    echo ""
    echo "  \e[33mImportant:\e[0m Always deploy from a clean, complete copy of your code."

    select_component "Which component do you want to deploy new code to?" all_components
    local comp="$REPLY"

    read -rp "Enter the full path to the source directory containing the new code for '$comp': " source_path
    if [ ! -d "$source_path" ]; then
        log_err "Source directory not found: $source_path"
        return
    fi

    local dest_path="$APP_PATH/$comp"

    log "Step 1: Previewing Changes"
    echo "Performing a dry-run of 'rsync' to show what would be updated..."

    if [[ "$comp" == "website" ]]; then
        sudo rsync -av --delete --dry-run "$source_path/" "$dest_path"
    else
        sudo rsync -av --exclude="venv/" --exclude="*.db" --dry-run "$source_path/" "$dest_path"
    fi

    echo ""
    log "Step 2: Confirm Deployment"
    echo "The following 'rsync' command will be executed to synchronize the directories:"
    if [[ "$comp" == "website" ]]; then
        echo -e "  \e[36msudo rsync -av --delete \"$source_path/\" \"$dest_path\"\e[0m"
    else
        echo -e "  \e[36msudo rsync -av \"$source_path/\" \"$dest_path\" --exclude=\"venv/\" --exclude=\"*.db\"\e[0m"
    fi

    read -rp "Are you sure you want to proceed with deployment to '$comp'? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Deployment cancelled."
        return
    fi

    log "Step 3: Deploying Files"
    if [[ "$comp" == "website" ]]; then
        sudo rsync -av --delete "$source_path/" "$dest_path"
        local web_user="web_$PROJECT"
        sudo chown -R "$web_user:$web_user" "$dest_path"
        sudo chmod -R 755 "$dest_path"
        reload_nginx
        log_ok "Website files deployed, permissions set, and NGINX reloaded."
    else
        sudo rsync -av --exclude="venv/" --exclude="*.db" "$source_path/" "$dest_path"
        sudo chown -R "$APP_USER:$APP_USER" "$dest_path"
        log_ok "Files synchronized and permissions set."

        log "Step 4: Restarting Service..."
        sudo systemctl restart "$PROJECT-$comp.service"
        log_ok "'$comp' service restarted to apply changes."
        sleep 1
        sudo systemctl status "$PROJECT-$comp.service" --no-pager --lines=5
    fi
}


deploy_code_url() {
    if ! check_dep "wget" || ! check_dep "tree"; then return; fi

    log "Deploy New Code from URL"
    echo "This tool downloads an archive (zip, tar.gz), shows its contents, and deploys it to a component."
    log "💡 Tip: Uploading Your Deployment Archive"
    echo ""
    printf "\n\e[33m%s\e[0m\n" "Need to deploy a local zip or tar.gz file?"
    printf " You can upload it first to a trusted temporary hosting service such as:\n"
    printf "  - \e[36mhttps://file.io\e[0m\n"
    printf "  - \e[36mhttps://tmpfiles.org\e[0m\n"
    printf "\nThen copy the download URL and paste it below when prompted.\n"
    printf "Your archive will be downloaded and deployed to the selected component.\n"
    pause


    select_component "Which component do you want to deploy to?" SELECTED_COMPONENTS
    local comp="$REPLY"

    read -rp "Enter the URL of the archive file (e.g., .zip, .tar.gz): " url
    if [ -z "$url" ]; then log_warn "No URL provided."; return; fi

    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'sudo rm -rf "$temp_dir"' EXIT RETURN

    log "Step 1: Downloading archive..."
    if ! sudo wget -O "$temp_dir/archive" "$url"; then
        log_err "Download failed. Please check the URL."
        return
    fi
    log_ok "Download complete."

    log "Step 2: Extracting archive..."
    if file "$temp_dir/archive" | grep -q 'gzip compressed data'; then
        sudo tar -xzf "$temp_dir/archive" -C "$temp_dir"
    elif file "$temp_dir/archive" | grep -q 'Zip archive data'; then
        if ! check_dep "unzip"; then return; fi
        sudo unzip "$temp_dir/archive" -d "$temp_dir"
    else
        log_err "Unsupported archive type. Only .zip and .tar.gz are supported."
        return
    fi
    sudo rm "$temp_dir/archive" # Clean up the downloaded archive file
    log_ok "Extraction complete."

    log "Step 3: Previewing Contents"
    echo "The following files were extracted from the archive:"
    echo "--------------------------------------------------------"
    sudo tree "$temp_dir"
    echo "--------------------------------------------------------"

    local dest_path="$APP_PATH/$comp/"
    log "Step 4: Confirm Deployment"
    echo "The contents of the archive will be copied to '$dest_path'."
    log_warn "This will overwrite any existing files with the same names."
    read -rp "Are you sure you want to proceed with deployment to '$comp'? (y/N): " confirm
    if [[ "$confirm" != [yY] ]]; then echo "Deployment cancelled."; return; fi

    log "Step 5: Deploying..."

    if [[ "$comp" == "website" ]]; then
        log_warn "This is a full sync. Files in the website folder that are NOT in the archive will be deleted."
        read -rp "Are you absolutely sure you want to continue? This will delete unmatched files. [y/N]: " confirm_website
        if [[ "$confirm_website" != [yY] ]]; then
            echo "Website deployment cancelled."
            return
        fi
        sudo rsync -av --delete "$temp_dir/" "$dest_path"
    else
        sudo rsync -av "$temp_dir/" "$dest_path"
    fi

    log_ok "Files copied successfully."

    log "Step 6: Setting Permissions and Reloading"
    if [[ "$comp" == "website" ]]; then
            local web_user="web_$PROJECT"
        sudo chown -R "$web_user:$web_user" "$dest_path"
        sudo chmod -R 755 "$dest_path"
        log_ok "Website permissions set. Reloading NGINX..."
        reload_website
    else
        sudo chown -R "$APP_USER:$APP_USER" "$dest_path"
        log_ok "Backend permissions set. Restarting service..."
        sudo systemctl restart "$PROJECT-$comp.service"
        log_ok "Service '$comp' restarted."
        sleep 1
        sudo systemctl status "$PROJECT-$comp.service" --no-pager --lines=5
    fi
}


manage_env() {
    if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services found."; return; fi

    log "Manage Environment Variables (.env)"
    select_component "Which service's .env file do you want to manage?" BACKEND_SERVICES
    local comp="$REPLY"
    local env_file="$APP_PATH/$comp/.env"

    echo "Selected .env file for '$comp' service."
    echo "1) View file"
    echo "2) Edit file (uses your default editor, e.g., nano)"
    read -rp "Your choice: " choice

    case $choice in
        1)
            log "Contents of $env_file:"
            sudo cat "$env_file"
            ;;
        2)
            log "Opening $env_file in your default editor..."
            echo "Save and exit the editor when you are done."
            sudo -E "${EDITOR:-nano}" "$env_file"
            read -rp "You have edited the .env file. Restart service '$comp' to apply changes? (y/N): " restart_confirm
            if [[ "$restart_confirm" == [yY] ]]; then
                sudo systemctl restart "$PROJECT-$comp.service"
                log_ok "Service '$comp' restarted."
            fi
            ;;
        *)
            log_warn "Invalid option."
            ;;
    esac
}

explore_database() {
    if ! check_dep "litecli" || ! check_dep "fzf"; then return; fi

    log "Searching for databases within project '$PROJECT'..."
    local db_files
    db_files=$(sudo find "$APP_PATH" -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \))

    if [ -z "$db_files" ]; then
        log_warn "No database files found for this project."
        return
    fi

    local selected_db
    selected_db=$(echo "$db_files" | fzf --prompt="Select a database to explore > " --height=40% --border)

    if [ -z "$selected_db" ]; then echo "No database selected."; return; fi

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

    sudo litecli "$selected_db"
}

view_tree() {
    if ! check_dep "tree"; then
        return
    fi
    log "Displaying directory tree for '$PROJECT' (max depth: 3, ignoring venv):"
    tree -L 3 -I 'venv' "$APP_PATH"
}

edit_component_file_fzf() {
  if ! check_dep "fzf"; then return; fi
  if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then
    log_err "No backend services found."
    return
  fi

  log "Scanning all component files..."
  local file_list=()
  local -A file_to_comp_map

  for comp in "${BACKEND_SERVICES[@]}"; do
    local comp_path="$APP_PATH/$comp"
    while IFS= read -r file; do
      local rel_path="${file#$comp_path/}"
      local display="[${comp}] $rel_path"
      file_list+=("$display")
      file_to_comp_map["$display"]="$comp:$file"
    done < <(sudo find "$comp_path" -type f ! -path "*/venv/*")
  done

  if [ ${#file_list[@]} -eq 0 ]; then
    log_warn "No editable files found in backend components."
    return
  fi

  local selection
  selection=$(printf '%s\n' "${file_list[@]}" | fzf --prompt="Select a file to edit > " --height=80% --border)
  if [[ -z "$selection" ]]; then
    log_warn "No file selected."
    return
  fi

  IFS=':' read -r comp full_path <<< "${file_to_comp_map["$selection"]}"

  log "Editing '$full_path' from component '$comp'..."
  sudo -E "${EDITOR:-nano}" "$full_path"

  echo ""
  read -rp "Restart service '$comp' to apply changes? (y/N): " restart_confirm
  if [[ "$restart_confirm" == [yY] ]]; then
    sudo systemctl restart "$PROJECT-$comp.service"
    log_ok "Service '$comp' restarted."
  else
    log "No restart performed."
  fi
}

# --- Maintenance & Danger Zone Functions ---
backup_menu() {
    log "Project Backup Menu"
    echo "This tool creates a compressed archive of your project's files."
    sudo mkdir -p "$BACKUP_ROOT"
    log_ok "Backups will be stored in '$BACKUP_ROOT'."
    echo ""
    echo "1) Backup FULL Project (Code + Data + Logs)"
    echo "2) Backup DATABASES Only"
    echo "3) Return to Main Menu"
    read -rp "Your choice: " choice

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    case $choice in
        1)
            local backup_file="$BACKUP_ROOT/${PROJECT}-full-backup-${timestamp}.tar.gz"
            log "Starting full project backup..."
            echo "This will archive the entire '$APP_PATH' directory, excluding 'venv' directories."
            sudo tar --exclude='**/venv' -czf "$backup_file" -C "$(dirname "$APP_PATH")" "$(basename "$APP_PATH")"
            log_ok "Full project backup complete!"
            echo "Archive created at: $backup_file"
            ;;
        2)
            if ! check_dep "sqlite3"; then return; fi
            local backup_file="$BACKUP_ROOT/${PROJECT}-db-backup-${timestamp}.tar.gz"
            local temp_db_dir
            temp_db_dir=$(mktemp -d)
            trap 'sudo rm -rf "$temp_db_dir"' RETURN

            log "Starting database-only backup..."
            echo "Searching for .db files and creating safe copies..."
            find "$APP_PATH" -type f -name "*.db" -print0 | while IFS= read -r -d $'\0' db_file; do
                local rel_path
                rel_path=$(realpath --relative-to="$APP_PATH" "$db_file")
                sudo mkdir -p "$temp_db_dir/$(dirname "$rel_path")"
                sudo sqlite3 "$db_file" ".backup '$temp_db_dir/$rel_path'"
                log_ok "Backed up: $rel_path"
            done
            sudo tar -czf "$backup_file" -C "$temp_db_dir" .
            log_ok "Database backup complete!"
            echo "Archive created at: $backup_file"
            ;;
        3) return ;;
        *) log_warn "Invalid choice." ;;
    esac
}

delete_project() {
    log_err "DANGER ZONE: This will permanently delete the '$PROJECT' project."
    echo "This includes all code, databases, logs, users, system services, and NGINX configurations."
    log_warn "This action CANNOT BE UNDONE. It is recommended to create a backup first."

    read -rp "To confirm, please type the project name ('$PROJECT'): " confirm_name

    if [[ "$confirm_name" != "$PROJECT" ]]; then
        err "Confirmation failed. Project deletion aborted."
    fi

    log "Proceeding with deletion..."

    for comp in "${BACKEND_SERVICES[@]}"; do
        local service_file="/etc/systemd/system/$PROJECT-$comp.service"
        log "Stopping, disabling, and deleting service: $PROJECT-$comp.service"
        sudo systemctl disable --now "$PROJECT-$comp.service" &>/dev/null || true
        if [ -f "$service_file" ]; then
            sudo rm -f "$service_file"
        fi
    done
    sudo systemctl daemon-reload
    log_ok "All systemd services stopped and deleted."

    if [[ "$HAS_WEBSITE" == "true" ]]; then sudo rm -f "/etc/nginx/sites-enabled/${PROJECT}-web.conf" "/etc/nginx/sites-available/${PROJECT}-web.conf"; fi
    if [[ "$HAS_BACKEND" == "true" ]]; then sudo rm -f "/etc/nginx/sites-enabled/${PROJECT}-api.conf" "/etc/nginx/sites-available/${PROJECT}-api.conf"; fi
    sudo nginx -t && sudo systemctl reload nginx &>/dev/null || log_warn "NGINX reload may fail if other configs are broken, this is OK during deletion."
    log_ok "NGINX configurations removed."

    if [ -f "/etc/logrotate.d/$PROJECT" ]; then
        log "Removing logrotate config..."
        sudo rm -f "/etc/logrotate.d/$PROJECT"
    fi

    local web_user="web_$PROJECT"
    sudo userdel -r "$APP_USER" &>/dev/null || true; log_ok "User '$APP_USER' deleted."
    if [[ "$HAS_WEBSITE" == "true" ]]; then
        sudo userdel -r "$web_user" &>/dev/null || true; log_ok "User '$web_user' deleted."
    fi

    log "Deleting project directory: $APP_PATH"
    sudo rm -rf "$APP_PATH"
    log_ok "Project directory deleted."

    log_ok "Project '$PROJECT' has been completely and permanently deleted."
    exit 0
}

show_help() {
    show_logo
    log "Project Operator Help"
    printf "\nThis script is your command center for a single, specific project ('%s').\n" "$PROJECT"

    printf "\n\e[36m%s\e[0m\n" "1. Main Operations"
    printf "   %s\n" "These are your day-to-day tools for checking on and managing the project."
    printf "   - \e[33m%s\e[0m: %s\n" "Show Info" "Get a quick summary of domains, paths, and components."
    printf "   - \e[33m%s\e[0m: %s\n" "Restart Service" "Use this after manual code changes to make them take effect."
    printf "   - \e[33m%s\e[0m: %s\n" "View Live Logs" "The most important debugging tool to see real-time app output."
    printf "   - \e[33m%s\e[0m: %s\n" "Check all backend apps health" "Verifies that all services are running and accessible from the internet."
    printf "   - \e[33m%s\e[0m: %s\n" "Reload Website" "Resets website file permissions and reloads NGINX."
    printf "   - \e[33m%s\e[0m: %s\n" "Reload NGINX" "Tests and reloads the global NGINX configuration."

    printf "\n\e[36m%s\e[0m\n" "2. Developer Tools"
    printf "   %s\n" "Tools to help you with the development and deployment cycle."
    printf "   - \e[33m%s\e[0m: %s\n" "Show Admin Keys" "Displays the secret admin keys for your backend services."
    printf "   - \e[33m%s\e[0m: %s\n" "Rotate JWT Secret" "Generates a new master key for signing tokens. Logs out all users."
    printf "   - \e[33m%s\e[0m: %s\n" "Deploy from Local" "Safely copies code from a folder on the server to an app and restarts it."
    printf "   - \e[33m%s\e[0m: %s\n" "Deploy from URL" "Downloads a .zip or .tar.gz from a URL and deploys it to a component."
    printf "   - \e[33m%s\e[0m: %s\n" "Manage .env" "Securely view or edit secrets like API keys."
    printf "   - \e[33m%s\e[0m: %s\n" "Explore Databases" "Finds this project's databases and lets you explore them with a friendly CLI."
    printf "   - \e[33m%s\e[0m: %s\n" "Open Service Shell" "Log in as the application's user, with its virtual environment activated."

    printf "\n\e[36m%s\e[0m\n" "3. Maintenance & Danger Zone"
    printf "   %s\n" "Powerful tools that should be used with care."
    printf "   - \e[33m%s\e[0m: %s\n" "Backup" "Create a full-project or database-only backup archive."
    printf "   - \e[33m%s\e[0m: %s\n" "DELETE Project" "Completely and irreversibly removes the project from the server."
}


show_menu() {
  clear
  show_logo
  echo "==================================================================================="
  echo "  Project Operator: $PROJECT"
  echo "==================================================================================="
  echo ""
  echo "--- Main ---"
  echo "  1) Show Project Info"
  echo "  2) Restart a Backend Service"
  echo "  3) View Live Logs"
  echo "  4) Check all backend apps health"
  echo "  5) Show Detailed Service Status"
  echo "  6) Reload Website Files & Permissions"
  echo "  N) Reload NGINX Configuration"
  echo ""
  echo "--- Developer Tools ---"
  echo "  A) Show Admin API Keys"
  echo "  J) Rotate JWT Secret..."
  echo "  P) Deploy from Local Path..."
  echo "  U) Deploy from URL..."
  echo "  E) Manage .env Variables..."
  echo "  D) Explore Project Databases (litecli)..."
  echo "  S) Open Service Shell"
  echo "  T) View Project Directory Tree"
  echo "  F) Edit Any File in a Backend Component (fzf)"
  echo ""
  echo "--- Maintenance & Danger Zone ---"
  echo "  B) Backup Menu..."
  echo "  X) DELETE this Project..."
  echo ""
  echo "==================================================================================="
  echo "  H) Help             Q) Quit"
  echo "==================================================================================="
  read -rp "Enter choice: " choice
}

# --- Main Menu Loop ---
while true; do
  show_menu
  case $choice in
    1) show_info; pause ;;
    2) restart_component; pause ;;
    3) view_logs; pause ;;
    4) check_health; pause ;;
    5) status_all; pause ;;
    6) reload_website; pause ;;
    [Nn]) reload_nginx; pause ;;

    [Aa]) show_admin_keys; pause ;;
    [Jj]) rotate_jwt_secret; pause ;;
    [Pp]) deploy_code_local; pause ;;
    [Uu]) deploy_code_url; pause ;;
    [Ee]) manage_env; pause ;;
    [Dd]) explore_database; pause ;;
    [Ss])
        if [ ${#BACKEND_SERVICES[@]} -eq 0 ]; then log_err "No backend services found."; pause; continue; fi
        select_component "Which service's shell do you want to open?" BACKEND_SERVICES
        comp="$REPLY"
        comp_path="$APP_PATH/$comp"

        log "Opening shell for '$comp'. Type 'exit' to return."
        echo "You are now operating as the '$APP_USER' user, in the correct directory, with the Python venv activated."
        log_warn "The user's HOME is temporarily set to '$comp_path' for this session."
        
        # CRITICAL FIX: Set the HOME environment variable for the sudo session.
        # This gives programs like nano and pip a writable directory for their cache/config files.
        # Use --init-file to ensure the (venv) prompt is displayed correctly.
        sudo -u "$APP_USER" HOME="$comp_path" bash -c "cd '$comp_path' && bash --init-file venv/bin/activate -i"
        ;;
    [Tt]) view_tree; pause ;;
    [Ff]) edit_component_file_fzf; pause ;;

    [Bb]) backup_menu; pause ;;
    [Xx]) delete_project ;;

    [Hh]) show_help; pause ;;
    [Qq]) echo "Exiting." && exit 0 ;;
    *) log_err "Invalid choice. Please try again."; pause ;;
  esac
done