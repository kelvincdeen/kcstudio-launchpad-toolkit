#!/bin/bash
#
# === KCStudio Launchpad V1.0 ===
#

set -euo pipefail
IFS=$'\n\t'

# --- Root Enforcement ---
if [ "$EUID" -ne 0 ]; then
    echo ""
    echo ""
    echo ""
    echo -e "\n\e[31m[X]\e[0m This script must be run as \e[1mroot\e[0m to \e[1muse & enjoy\e[0m all its \e[1mfeatures\e[0m flawlessly."
    echo -e "Please \e[1mrun\e[0m it \e[1magain\e[0m with:"
    echo ""
    echo -e "  \e[36msudo ./$(basename "$0")\e[0m"
    echo ""
    echo ""
    echo ""
    echo ""
    exit 1
fi

# --- Startup animation ---
launch_kcstudio() {
    clear

    # --- ANSI Colors ---
    YELLOW=$'\033[1;33m'
    ORANGE=$'\033[0;33m'
    DARKGRAY=$'\033[0;33m'
    WHITE=$'\033[1;37m'
    RESET=$'\033[0m'

    # --- Add vertical padding ---
    blank_lines=60
    for ((i = 0; i < blank_lines; i++)); do
        echo ""
    done

    # --- Rocket ASCII ---
    rocket_lines=(
    "                                   ${YELLOW}████${RESET}                                "
    "                                  ${YELLOW}█${ORANGE}▓${YELLOW}█████${RESET}                               "
    "                                 ${YELLOW}█${ORANGE}▓${YELLOW}███████${RESET}                              "
    "                               ${YELLOW}██${ORANGE}▓▓${YELLOW}████████${RESET}                             "
    "                              ${YELLOW}██${ORANGE}▓▓▓▓${YELLOW}████████${RESET}                            "
    "                             ${DARKGRAY}▒▒▒▒▒▒▒▒▒${ORANGE}▓▓▓▓▓▓▓${RESET}                           "
    "                            ${DARKGRAY}▒▒▒▒▒▒▒▒▒▒${ORANGE}▓▓▓▓▓▓▓${RESET}                           "
    "                            ${DARKGRAY}▒▒▒▒▒▒${ORANGE}▓▓${YELLOW}███${ORANGE}▓▓▓▓▓▓▓${RESET}                          "
    "                            ${DARKGRAY}▒▒▒▒▒${ORANGE}▓${YELLOW}████████${ORANGE}▓▓▓▓${RESET}                          "
    "                           ${DARKGRAY}▒▒▒▒▒${ORANGE}▓▓${YELLOW}███████${ORANGE}▓▓▓▓${RESET}                          "
    "                           ${DARKGRAY}▒▒▒▒▒${ORANGE}▓▓${YELLOW}███████${ORANGE}▓▓▓▓▓${RESET}                        "
    "                           ${DARKGRAY}▒▒▒▒▒${ORANGE}▓${YELLOW}█████████${ORANGE}▓▓▓▓▓${RESET}                        "
    "                           ${DARKGRAY}▒▒▒▒▒▒${ORANGE}▓${YELLOW}██████${ORANGE}▓▓▓▓▓▓${RESET}                         "
    "                           ${DARKGRAY}▒▒▒▒▒▒▒▒${ORANGE}▓▓▓▓▓▓▓▓▓▓▓${RESET}                         "
    "                           ${DARKGRAY}▒▒▒▒▒▒▒▒${ORANGE}▓▓▓▓▓▓▓▓▓▓▓${RESET}                         "
    "                          ${ORANGE}▒▓▓▓${DARKGRAY}▒▒▒▒${ORANGE}▓${YELLOW}█████${ORANGE}▓▓▓▓${YELLOW}█▓▓${ORANGE}▒${RESET}                        "
    "                        ${ORANGE}▒▒▓▓▓▓${DARKGRAY}▒▒▒▒▒▒${ORANGE}▓▓▓▓▓▓▓${YELLOW}█▓▓${ORANGE}▒▓${RESET}                       "
    "                       ${ORANGE}▒▒▓▓▓▓▓▓${DARKGRAY}▒▒▒▒▒${ORANGE}▓▓▓▓▓▓${YELLOW}██▓▓▓${ORANGE}▒▓▓${RESET}                    "
    "                      ${ORANGE}▒▒▓▓▓▓▓▓▓${DARKGRAY}▒▒▒▒▒${YELLOW}▓█▓▓▓▓${YELLOW}█▓▓▓▓▓▓▓${RESET}                    "
    "                     ${ORANGE}▒▒▓▓▓▓▓▓▓▓▓${DARKGRAY}▒▒▒▒${YELLOW}▓█▓▓▓▓${YELLOW}██▓▓▓▓▓▒▓▓${RESET}                   "
    "                     ${ORANGE}▒▒▓▓▓▓▓▓▓▓▓▓${DARKGRAY}▒▒▒${YELLOW}▓██▓▓▓${YELLOW}█▓▓▓▓▓▓▓▓${RESET}                    "
    "                     ${ORANGE}▒▒▓▓▓▓▓${YELLOW} ███▓▓▓${DARKGRAY}▒${YELLOW}▓██████ ${ORANGE}▓▓▓▓▓▓${RESET}                    "
    "                     ${ORANGE}▒▒▓▓▓▓${YELLOW}   █████${DARKGRAY}▒${YELLOW}▓█████   ${ORANGE}▓▓▓▓▓▓${RESET}                    "
    "                      ${ORANGE}▒▓▓▓${YELLOW}     ▓▓▓▓${DARKGRAY}▒${YELLOW}▓▓▓▓▓     ${ORANGE}▓▓▓▓${RESET}                     "
    "                      ${ORANGE}▒▓▓▓${YELLOW}    ▓▓▓${DARKGRAY}▒▒${YELLOW}▓▓▓▓▓▓█     ${ORANGE}▓▓▓${RESET}                     "
    "                       ${ORANGE}▓▓${YELLOW}     ▓▓▓${DARKGRAY}▒▒▒${YELLOW}▓▓▓▓▓${RESET}                              "
    "                              ${YELLOW}▓▓▓▓${DARKGRAY}▒▒${YELLOW}▓▓▓▓▓${RESET}                              "
    "                              ${YELLOW}▓▓▓▓▓▓▓▓▓▓${RESET}                               "
    "                               ${YELLOW}▓▓▓▓▓▓▓▓${RESET}                                 "
    "                                 ${YELLOW}▓▓▓▓▓▓${RESET}                                 "
    "                                  ${YELLOW}▓▓▓${RESET}${ORANGE}█${RESET}                                  "
    "                                   ${YELLOW}▓${RESET}                                    "
    ""
    )

    # --- KCSTUDIO.NL Logo ASCII ---
    logo_lines=(
    "${WHITE}██╗  ██╗ ██████╗███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗    ███╗   ██╗██╗${RESET}"
    "${WHITE}██║ ██╔╝██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗   ████╗  ██║██║${RESET}"
    "${WHITE}█████╔╝ ██║     ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║   ██╔██╗ ██║██║${RESET}"
    "${WHITE}██╔═██╗ ██║     ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║   ██║╚██╗██║██║${RESET}"
    "${WHITE}██║  ██╗╚██████╗███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝██╗██║ ╚████║███████╗${RESET}"
    "${WHITE}╚═╝  ╚═╝ ╚═════╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝${RESET}"
    ""
    )

    extra_lines_b=(
    "${WHITE}   ██╗      █████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗  ██╗██████╗  █████╗ ██████╗${RESET}"
    "${WHITE}   ██║     ██╔══██╗██║   ██║████╗  ██║██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗${RESET}"
    "${WHITE}   ██║     ███████║██║   ██║██╔██╗ ██║██║     ███████║██████╔╝███████║██║  ██║${RESET}"
    "${WHITE}   ██║     ██╔══██║██║   ██║██║╚██╗██║██║     ██╔══██║██╔═══╝ ██╔══██║██║  ██║${RESET}"
    "${WHITE}   ███████╗██║  ██║╚██████╔╝██║ ╚████║╚██████╗██║  ██║██║     ██║  ██║██████╔╝${RESET}"
    "${WHITE}   ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═════╝${RESET}"
    )







    # --- Rocket Launch Reveal ---
    for line in "${rocket_lines[@]}"; do
        echo -e "$line"
        sleep 0.02
    done

    # --- KCSTUDIO Logo Reveal ---
    sleep 0.2
    echo ""
    for line in "${logo_lines[@]}"; do
        echo -e "$line"
        sleep 0.04
    done
    # --- Launchpad Logo Reveael ---
    for line in "${extra_lines_b[@]}"; do
        echo -e "$line"
        sleep 0.04
    done
}

# --- Helper Functions ---
log() { echo -e "\n\e[32m[+]\e[0m $1"; }
warn() { echo -e "\n\e[33m[!]\e[0m $1"; }
err() { echo -e "\n\e[31m[!] \e[31m$1\e[0m" >&2; exit 1; }
prompt() { read -rp "$(echo -e "\e[36m[?]\e[0m $1 ")" "$2"; }
pause() { echo ""; read -rp "Press [Enter] to continue..."; }

# --- Menu Display & Core Logic ---
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

run_script() {
    local script_name=$1
    # Bepaal de directory waar het HUIDIGE script (KCstudioLaunchpadV1.0.sh) staat.
    local toolkit_dir
    toolkit_dir=$(dirname "$(realpath "$0")")
    
    local script_path="${toolkit_dir}/${script_name}"

    if [ ! -f "$script_path" ]; then
        err "Script '$script_name' not found at expected path: '$script_path'. Please ensure all toolkit scripts are in the same directory."
    fi
    
    if [ ! -x "$script_path" ]; then
        warn "Script '$script_name' is not executable. Attempting to set permissions..."
        sudo chmod +x "$script_path" || err "Could not set execute permissions on '$script_path'. Please run 'sudo chmod +x $script_path' manually."
    fi

    log "Executing '$script_name'..."
    "$script_path"
}

verify_os() {
    # log "Verifying Operating System..."

    if [ ! -f /etc/os-release ]; then
        err "Cannot determine OS version: /etc/os-release not found. Aborting."
    fi

    # Source the os-release file to get variables like ID and VERSION_ID
    # This is safe as it's a standard system file.
    . /etc/os-release

    if [ "$ID" != "ubuntu" ] && [ "$VERSION_ID" != "24.04" ]; then
        # log "System check passed: Ubuntu 24.04 LTS detected."
    # else
        # If it fails, print a detailed error message before exiting.
        echo ""
        echo -e "  \e[31m[X] Incompatible Operating System Detected.\e[0m"
        echo "  --------------------------------------------------------"
        echo -e "  \e[33mExpected:\e[0m Ubuntu 24.04 LTS"
        echo -e "  \e[31mFound:\e[0m    $PRETTY_NAME"
        echo "  --------------------------------------------------------"
        # Now use the 'err' function to print the final message and exit.
        err "This toolkit is designed exclusively for Ubuntu 24.04 to ensure stability."
    fi
}

# --- Documentation Pages ---
show_docs_main() {
    while true; do
        show_logo
        echo "==================================================================================="
        echo "           Toolkit Documentation & User Guides"
        echo "==================================================================================="
        echo
        echo "--- The Workflow ---"
        echo "  [1] Step 1: Secure Core VPS Setup (The Foundation)"
        echo "  [2] Step 2: Create Project (The Architect)"
        echo "  [3] Step 3: Manage App (The Project Manager)"
        echo "  [4] Step 4: Server Maintenance (The Operator)"
        echo
        echo "--- Guides & Reference ---"
        echo "  [5] The 'Big Picture': How It All Works Together"
        echo "  [6] How to Use the Generated API"
        echo "  [7] Full API Reference"
        echo "  [8] Manual Commands & Emergency Cheatsheet"
        echo "  [9] About & The Toolkit Philosophy"
        echo
        echo "  [M] Return to Main Menu"
        echo "==================================================================================="
        prompt "Select a topic to learn about: " choice

        case $choice in
            1) docs_secure_vps ;;
            2) docs_create_project ;;
            3) docs_manage_app ;;
            4) docs_server_maintenance ;;
            5) docs_big_picture ;;
            6) docs_how_to_use_api ;;
            7) docs_api_reference ;;
            8) docs_manual_commands ;;
            9) docs_philosophy ;;
            [Mm]) return 0 ;;
            *) warn "Invalid choice."; pause ;;
        esac
    done
}

docs_secure_vps() {
    show_logo
    log "Documentation: Secure Core VPS Setup (v5.1)"
    printf "\e[36m%s\e[0m\n" "--- I. PURPOSE ---"
    printf " %s\n" "This is the **first script you should ever run** on a fresh, new server."
    printf " %s\n" "Its sole purpose is to transform a generic, vulnerable server into a hardened,"
    printf " %s\n" "production-ready foundation. It is designed to be run **only once**."

    printf "\n\e[36m%s\e[0m\n" "--- II. KEY ACTIONS & FEATURES ---"
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Installs Core Packages" "Upgrades the OS and installs essentials like NGINX, UFW, Fail2Ban, Certbot, and LiteCLI."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Checks Time Sync (NTP)" "Verifies the server's clock is synchronized, preventing SSL and JWT token errors."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Pre-registers Certbot" "Prompts you for your email to pre-register with Let's Encrypt, ensuring"
    printf "    %s\n" "smoother project creation later."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Creates a Secure Deploy User" "Creates a non-root user with passwordless \`sudo\` for all future work."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Hardens SSH Access" "Disables password login, forces SSH key use, moves SSH to a custom port,"
    printf "    %s\n" "and enforces modern, secure encryption ciphers."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Sets up UFW Firewall" "Configures the firewall to deny all incoming traffic by default, only allowing"
    printf "    %s\n" "your custom SSH port and web traffic (HTTP/S)."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Configures Fail2Ban" "Sets up automated intrusion prevention to block IPs that try to brute-force SSH."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Hardens NGINX" "Creates secure global settings and a 'black hole' default site to prevent info leaks."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Enables Auto-Updates" "Configures \`unattended-upgrades\` to automatically install critical security patches."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Runs Security Audit" "Finishes by running \`lynis\` to give you a report card on the server's new hardened state."
    pause
}

docs_create_project() {
    show_logo
    log "Documentation: Create Project (v9.1)"
    printf "\e[36m%s\e[0m\n" "--- I. PURPOSE ---"
    printf " %s\n" "This is the **architect**. It doesn't just configure a server; it **writes a huge"
    printf " %s\n" "amount of high-quality, secure backend code for you.**"

    printf "\n\e[36m%s\e[0m\n" "--- II. GENERATED COMPONENTS & FEATURES ---"
    printf "  ✅ \e[33m%s\e[0m: %s\n" "auth Service" "A complete user authentication system out of the box."
    printf "    - \e[32m%s\e[0m: %s\n" "Magic Link Login" "Passwordless, email-based login flow using Resend."
    printf "    - \e[32m%s\e[0m: %s\n" "Professional Emails" "Sends a professionally designed HTML email for the magic link."
    printf "    - \e[32m%s\e[0m: %s\n" "JWT Session Tokens" "Industry-standard, secure session management."
    printf "    - \e[32m%s\e[0m: %s\n" "Full Profile Management" "Endpoints for /me, /update-me, /public-profile, and /delete-me."
    printf "    - \e[32m%s\e[0m: %s\n" "Rich Profiles" "Schema includes display name, photo, bio, and a flexible JSON social links field."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "database Service" "A powerful and secure data API using SQLite."
    printf "    - \e[32m%s\e[0m: %s\n" "Flexible Schema" "Supports slug, title, type, category, tags, and a freeform JSON \`data\` field."
    printf "    - \e[32m%s\e[0m: %s\n" "Full CRUD & Search" "Pre-built endpoints for creating, reading, updating, deleting, and searching."
    printf "    - \e[32m%s\e[0m: %s\n" "Admin & Public APIs" "Separate endpoints for admin-only listing (\`/listall\`) and public listing (\`/listpublic\`)."
    printf "    - \e[32m%s\e[0m: %s\n" "Data Ownership" "Generated code ensures users can only edit or delete content they own."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "storage Service" "A robust system for handling file uploads."
    printf "    - \e[32m%s\e[0m: %s\n" "Authenticated Actions" "All uploads and deletions are protected and require a valid user token."
    printf "    - \e[32m%s\e[0m: %s\n" "Full File Management" "Includes endpoints for uploading, downloading, listing, and deleting files."
    printf "    - \e[32m%s\e[0m: %s\n" "Secure & Organized" "Uses secure, unguessable IDs and sanitizes filenames."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "app Service" "A blank canvas for your custom business logic, with example endpoints."
    printf "    - \e[32m%s\e[0m: %s\n" "Example Endpoints" "Includes public, user-authenticated, and admin-key-protected examples."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "website Host" "A properly configured NGINX site to serve your static frontend."

    printf "\n\e[36m%s\e[0m\n" "--- III. OTHER KEY ACTIONS ---"
    printf "  - \e[32m%s\e[0m: %s\n" "CORS Enabled" "All backend services include CORS middleware to allow your frontend to connect."
    printf "  - \e[32m%s\e[0m: %s\n" "Isolated Infrastructure" "Creates dedicated users, Python virtual environments, and systemd services for each project."
    printf "  - \e[32m%s\e[0m: %s\n" "Automated Configuration" "Handles NGINX, SSL, and log rotation automatically."
    printf "  - \e[32m%s\e[0m: %s\n" "Dependency Management" "Generates a \`requirements.txt\` file for reproducible builds."
    printf "  - \e[32m%s\e[0m: %s\n" "Full Restore Capability" "Can restore a complete project from a backup archive."
    pause
}

docs_manage_app() {
    show_logo
    log "Documentation: Manage App (v4.3.0)"
    printf "\e[36m%s\e[0m\n" "--- I. PURPOSE ---"
    printf " %s\n" "This is the **project manager**. It is your day-to-day command center for all"
    printf " %s\n" "operations related to a **single, specific application** that is already deployed."

    printf "\n\e[36m%s\e[0m\n" "--- II. KEY FEATURES ---"
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Live Log Streaming" "Instantly tail the logs for any backend service to debug issues in real-time."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Guided Code Deployment" "Deploy code from a local path on the server or directly from a URL"
    printf "    %s\n" "(e.g., a GitHub release .zip). Includes a dry-run preview to prevent mistakes."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Interactive Database Explorer" "Finds your project's databases and lets you explore them with"
    printf "    %s\n" "the powerful and user-friendly \`litecli\` tool."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "JWT Secret Rotation" "A critical security utility to generate a new master key for signing"
    printf "    %s\n" "tokens, instantly invalidating all active user sessions."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Secure Secret Management" "View or edit API keys and other secrets in your \`.env\` files."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Effortless Backups" "Create a full-project backup (code + data) or a safe, database-only backup."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Direct Shell Access" "Opens a shell as the application's user with its Python venv already activated."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "The 'Big Red Button'" "Completely and cleanly removes every trace of a project from the server."
    pause
}

docs_server_maintenance() {
    show_logo
    log "Documentation: Server Maintenance (v1.2)"
    printf "\e[36m%s\e[0m\n" "--- I. PURPOSE ---"
    printf " %s\n" "This is the **server operator**. Use this script to manage the health and"
    printf " %s\n" "utilities of the **entire server as a whole**, not just one specific project."

    printf "\n\e[36m%s\e[0m\n" "--- II. KEY FEATURES ---"
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Interactive Diagnostics" "Launch \`htop\` for real-time process viewing or \`ncdu\` to interactively"
    printf "    %s\n" "explore what's taking up disk space."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "GUI File Browser" "Launch Midnight Commander (\`mc\`), a powerful, two-pane visual file manager"
    printf "    %s\n" "for easy server navigation and file operations right in your terminal."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Log Viewers" "Quickly check the latest SSH login attempts (\`auth.log\`) and firewall"
    printf "    %s\n" "activity (\`ufw.log\`) directly from the menu."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Global Database Explorer" "Finds and lets you explore **any** SQLite database on the server"
    printf "    %s\n" "with the friendly \`litecli\` interface."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Download Files from URL" "A simple wizard to fetch files from the web directly into a"
    printf "    %s\n" "dedicated, non-web-served folder in \`/var/www/kcstudio/downloads\`."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Powerful Utilities" "Manage any systemd service with a searchable \`fzf\` interface, add cron jobs with a"
    printf "    %s\n" "wizard, check SSL status, or add/change a swap file."
    printf "  ✅ \e[33m%s\e[0m: %s\n" "Traffic Analysis" "Generate a beautiful \`GoAccess\` HTML report from your NGINX logs to see"
    printf "    %s\n" "who is visiting your sites and what pages are popular."
    pause
}

docs_big_picture() {
    show_logo
    log "Documentation: The 'Big Picture' Workflow"
    printf "\e[36m%s\e[0m\n" "--- I. THE PHILOSOPHY: A GUIDED PATH ---"
    printf " %s\n" "This toolkit isn't just a collection of scripts; it's a logical workflow."
    printf " %s\n" "It's designed to guide you through the entire process of launching and maintaining a"
    printf " %s\n" "professional-grade application, with four 'assistants' to help you at each stage."

    printf "\n\e[36m%s\e[0m\n" "--- II. THE RECOMMENDED WORKFLOW ---"
    printf " \e[33m%s\e[0m\n" "Step 1: PREPARE THE GROUND (Run Once Per Server)"
    printf "   \e[35m->\e[0m %s\n" "Tool: \`Secure Core VPS Setup\`"
    printf "   \e[35m->\e[0m %s\n" "Goal: To turn a generic server into your personal, secure fortress."

    printf "\n \e[33m%s\e[0m\n" "Step 2: CONSTRUCT THE MASTERPIECE (Run Once Per Project)"
    printf "   \e[35m->\e[0m %s\n" "Tool: \`Create Project\`"
    printf "   \e[35m->\e[0m %s\n" "Goal: To build and deploy a new, complete, full-stack application from scratch."

    printf "\n \e[33m%s\e[0m\n" "Step 3: MANAGE THE ESTATE (Run as Needed for One Project)"
    printf "   \e[35m->\e[0m %s\n" "Tool: \`Manage App\`"
    printf "   \e[35m->\e[0m %s\n" "Context: You are working on **one specific project**."
    printf "   \e[35m->\e[0m %s\n" "Tasks: Updating Python code, checking that project's logs, creating a backup."

    printf "\n \e[33m%s\e[0m\n" "Step 4: OPERATE THE ENTIRE PROPERTY (Run as Needed for the Whole Server)"
    printf "   \e[35m->\e[0m %s\n" "Tool: \`Server Maintenance\`"
    printf "   \e[35m->\e[0m %s\n" "Context: You are concerned with the **health of the entire server**."
    printf "   \e[35m->\e[0m %s\n" "Tasks: 'Why is the server slow?', 'Is the disk full?', 'Let me browse the filesystem.'"
    pause
}

# CORRECTED FUNCTION: Uses printf with explicit newlines for robustness.
docs_how_to_use_api() {
    show_logo
    log "Guide: How to Use the Generated API"
    printf "\e[36m%s\e[0m\n" "--- I. WHAT IS AN API? ---"
    printf " %s\n" "An API (Application Programming Interface) is a set of rules that allows your"
    printf " %s\n" "frontend (like a React or Vue app) to talk to your backend services."
    printf " %s\n" "Your frontend sends requests (e.g., 'get me this user's data'), and the API"
    printf " %s\n" "sends back responses (usually in a format called JSON)."

    printf "\n\e[36m%s\e[0m\n" "--- II. TESTING WITH CURL ---"
    printf " %s\n" "\`curl\` is a command-line tool for making web requests. It's perfect for testing."
    printf " %s\n" "Let's say your API domain is \`api.example.com\`. Here's how to test a public endpoint:"
    printf "   \e[35m$\e[0m \e[32mcurl https://api.example.com/v1/app/public-info\e[0m\n"
    printf "   \e[90m=> {\"message\":\"This is a public endpoint...\"}\e[0m\n"

    printf "\n\e[36m%s\e[0m\n" "--- III. AUTHENTICATION: TWO TYPES OF KEYS ---"
    printf " %s\n" "Your API has two levels of security:"
    printf "  \e[33m1. JWT (JSON Web Token)\e[0m: %s\n" "A temporary key for a specific user's session."
    printf "     - \e[90m%s\e[0m\n" "This is what your frontend uses after a user logs in."
    printf "     - \e[90m%s\e[0m\n" "You send it in a special 'Authorization' header."
    printf "   \e[35m$\e[0m \e[32mcurl -H \"Authorization: Bearer <your_jwt_here>\" https://api.example.com/v1/app/user/secret-data\e[0m\n"
    printf "  \e[33m2. Admin API Key\e[0m: %s\n" "A permanent, powerful key for server-to-server tasks."
    printf "     - \e[90m%s\e[0m\n" "NEVER use this in a public frontend. It has admin privileges."
    printf "     - \e[90m%s\e[0m\n" "You send it in a special 'X-Admin-API-Key' header."
    printf "   \e[35m$\e[0m \e[32mcurl -H \"X-Admin-API-Key: <your_admin_key_here>\" https://api.example.com/v1/app/admin/system-status\e[0m\n"
    printf "\n %s\n" "You can find your Admin API keys using the 'Manage App' script."
    pause
}

# CORRECTED FUNCTION: Uses printf for each line for maximum compatibility and custom styling.
_display_styled_api_reference() {
    (
    printf "\n"
    printf "  \e[1;36m%s\e[0m\n" "🚀 KCStudio Launchpad API Reference"
    printf "  %s\n" "A comprehensive reference for all auto-generated API endpoints."
    printf "  %s\n" "Check launchpad.kcstudio.nl/api-docs for full documentation."
    printf "\n"
    printf "  \e[1;33m%s\e[0m\n" "General Notes"
    printf "  \e[90m%s\e[0m\n" "----------------------------------------------------------------"
    printf "  \e[32m%s\e[0m \e[37m%s\e[0m\n" "∙" "Authentication: JWT requires \`Authorization: Bearer <token>\`."
    printf "  \e[32m%s\e[0m \e[37m%s\e[0m\n" "∙" "Admin Key requires \`X-Admin-API-Key: <key>\`."
    printf "  \e[32m%s\e[0m \e[37m%s\e[0m\n" "∙" "Base URL: All paths are prefixed with \`/v1\`."
    printf "\n"
    printf "\n"

    # --- AUTH SERVICE ---
    printf "  \e[1;36m%s\e[0m\n" "/v1/auth"
    printf "  \e[37m%s\e[0m\n" "Handles user authentication, registration, and profile management."
    printf "  \e[90m%s\e[0m\n" "----------------------------------------------------------------"
    printf "    \e[1;37m%s\e[0m\n" "GET /health"
    printf "    \e[90m%s\e[0m\n" "  Checks the health of the authentication service."
    printf "    \e[1;37m%s\e[0m\n" "POST /login"
    printf "    \e[90m%s\e[0m\n" "  Initiates a passwordless \"magic link\" login process for a user."
    printf "    \e[1;37m%s\e[0m\n" "POST /verify"
    printf "    \e[90m%s\e[0m\n" "  Verifies a magic link token to complete login and issue a JWT."
    printf "    \e[1;37m%s\e[0m\n" "GET /me"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Retrieves the profile of the currently authenticated user."
    printf "    \e[1;37m%s\e[0m\n" "PUT /me"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Updates the profile of the currently authenticated user."
    printf "    \e[1;37m%s\e[0m\n" "GET /public-profile/{user_id}"
    printf "    \e[90m%s\e[0m\n" "  Retrieves the public portions of a user's profile."
    printf "    \e[1;37m%s\e[0m\n" "DELETE /delete-me"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Permanently deletes the current user's account."
    printf "\n\n"

    # --- DATABASE SERVICE ---
    printf "  \e[1;36m%s\e[0m\n" "/v1/database"
    printf "  \e[37m%s\e[0m\n" "A general-purpose data API for creating and managing structured content."
    printf "  \e[90m%s\e[0m\n" "----------------------------------------------------------------"
    printf "    \e[1;37m%s\e[0m\n" "GET /health"
    printf "    \e[90m%s\e[0m\n" "  Checks the health of the database service."
    printf "    \e[1;37m%s\e[0m\n" "GET /listall"
    printf "    \e[90m%s\e[0m\n" "  (Admin Key Auth) Retrieves all entries with admin filtering."
    printf "    \e[1;37m%s\e[0m\n" "GET /listpublic"
    printf "    \e[90m%s\e[0m\n" "  Retrieves a paginated list of 'published' entries."
    printf "    \e[1;37m%s\e[0m\n" "GET /search"
    printf "    \e[90m%s\e[0m\n" "  Searches published entries by a keyword."
    printf "    \e[1;37m%s\e[0m\n" "GET /retrieve/{slug}"
    printf "    \e[90m%s\e[0m\n" "  Retrieves a single published entry by its slug."
    printf "    \e[1;37m%s\e[0m\n" "POST /create"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Creates a new entry owned by the user."
    printf "    \e[1;37m%s\e[0m\n" "PUT /update/{slug}"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Updates an entry if the user is the owner."
    printf "    \e[1;37m%s\e[0m\n" "DELETE /delete/{slug}"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Deletes an entry if the user is the owner."
    printf "\n\n"

    # --- STORAGE SERVICE ---
    printf "  \e[1;36m%s\e[0m\n" "/v1/storage"
    printf "  \e[37m%s\e[0m\n" "Handles secure file uploads, downloads, and management."
    printf "  \e[90m%s\e[0m\n" "----------------------------------------------------------------"
    printf "    \e[1;37m%s\e[0m\n" "GET /health"
    printf "    \e[90m%s\e[0m\n" "  Checks the health of the storage service."
    printf "    \e[1;37m%s\e[0m\n" "POST /upload"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Uploads a file via multipart/form-data."
    printf "    \e[1;37m%s\e[0m\n" "GET /download/{file_id}"
    printf "    \e[90m%s\e[0m\n" "  Downloads a file publicly by its ID."
    printf "    \e[1;37m%s\e[0m\n" "GET /list"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Lists metadata for all files owned by the user."
    printf "    \e[1;37m%s\e[0m\n" "DELETE /delete/{file_id}"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) Deletes a file if the user is the owner."
    printf "\n\n"

    # --- APP SERVICE ---
    printf "  \e[1;36m%s\e[0m\n" "/v1/app"
    printf "  \e[37m%s\e[0m\n" "Your core business logic. A template for you to build upon."
    printf "  \e[90m%s\e[0m\n" "----------------------------------------------------------------"
    printf "    \e[1;37m%s\e[0m\n" "GET /health"
    printf "    \e[90m%s\e[0m\n" "  Checks the health of the main application service."
    printf "    \e[1;37m%s\e[0m\n" "GET /public-info"
    printf "    \e[90m%s\e[0m\n" "  An example public endpoint."
    printf "    \e[1;37m%s\e[0m\n" "GET /user/secret-data"
    printf "    \e[90m%s\e[0m\n" "  (JWT Auth) An example endpoint protected by user authentication."
    printf "    \e[1;37m%s\e[0m\n" "GET /admin/system-status"
    printf "    \e[90m%s\e[0m\n" "  (Admin Key Auth) An example endpoint protected by the Admin API Key."
    printf "\n"
    ) | less -R
}

docs_api_reference() {
    show_logo
    log "Full API Reference"
    printf " %s\n" "This is a summary of all API endpoints for the generated services."
    printf " %s\n" "For full request/response models, please see the OpenAPI .yml file."
    read -p "Press [Enter] to display the reference (use arrow keys to scroll, 'q' to quit)..."
    _display_styled_api_reference
}

docs_manual_commands() {
    show_logo
    log "Documentation: Manual Commands & Emergency Cheatsheet"
    printf "\e[36m%s\e[0m\n" "--- WHEN THE BUTLER ISN'T ENOUGH ---"
    printf " %s\n" "This toolkit covers 95% of common tasks. For fine-grained control or"
    printf " %s\n" "emergencies, you need to use the command line. All commands should be run"
    printf " %s\n" "as your deploy user, using \`sudo\` when necessary."

    printf "\n\e[33m%s\e[0m\n" "Networking & Firewall"
    printf "  %-40s %s\n" "sudo ufw status verbose" "See detailed firewall rules."
    printf "  %-40s %s\n" "sudo ufw allow 5432/tcp" "Example: Open a port (e.g., for PostgreSQL)."
    printf "  %-40s %s\n" "sudo ufw delete allow 5432/tcp" "Example: Close a port."
    printf "  %-40s %s\n" "curl ifconfig.me" "Quickly find your server's public IP address."
    printf "  %-40s %s\n" "ss -tulnp" "See all listening ports and the programs using them."


    printf "\n\e[33m%s\e[0m\n" "Services & Processes"
    printf "  %-40s %s\n" "sudo systemctl status <service>" "Check if a service is running (e.g., \`nginx.service\`)."
    printf "  %-40s %s\n" "sudo journalctl -fu <service>" "Follow the live systemd journal for a service."
    printf "  %-40s %s\n" "htop" "An interactive process viewer (better than \`top\`)."

    printf "\n\e[33m%s\e[0m\n" "File System"
    printf "  %-40s %s\n" "ls -la /path/to/dir" "List files with permissions, owner, and size."
    printf "  %-40s %s\n" "sudo chown user:group /path/to/file" "Change a file's owner."
    printf "  %-40s %s\n" "sudo chmod 755 /path/to/file" "Change a file's permissions."
    printf "  %-40s %s\n" "scp -P <port> user@ip:/remote/path ." "Copy a file FROM the server."
    printf "  %-40s %s\n" "scp -P <port> local_file user@ip:/path/" "Copy a file TO the server."

    pause
}

docs_philosophy() {
    show_logo
    log "About & The Toolkit Philosophy"
    printf "\n"
    printf " \e[1;33m%s\e[0m\n" "This is a Toolkit for People Who Just Want to Ship Their Damn Project."
    printf "  %s\n" "Let's be honest. You have an idea. You build a cool little app. And then you hit the wall."
    printf "  %s\n" "The wall of modern DevOps. A thousand tutorials, a dozen config files, and an ocean of"
    printf "  %s\n" "YAML stand between your code and a public URL. This toolkit is a battering ram for that wall."

    printf "\n"
    printf " \e[1;33m%s\e[0m\n" "I'm Not an Expert. I Built This Because I Was Scared of the Command Line."
    printf "  %s\n" "I'm a builder, not a sysadmin. I was tired of the confusing, error-prone mess of manual server"
    printf "  %s\n" "setup. So I built a personal server butler to automate the scary parts and let me get back to"
    printf "  %s\n" "what I love: creating things. This is the result of a caffeine-fueled learning sprint, not"
    printf "  %s\n" "decades of experience. It's my learning journey, codified."

    printf "\n"
    printf " \e[1;33m%s\e[0m\n" "The Philosophy is Simple: Control, Not Complexity."
    printf "  \e[36m∙ No Docker, No Kubernetes:\e[0m\n"
    printf "    %s\n" "Not because they're bad, but because for a soloist, they can be a heavy, abstract"
    printf "    %s\n" "layer you don't need. This is about owning your stack, top to bottom."
    printf "  \e[36m∙ Readable Scripts:\e[0m\n"
    printf "    %s\n" "You can read every command the butler executes. There is no magic. It's a powerful way"
    printf "    %s\n" "to learn what's actually happening on your server."
    printf "  \e[36m∙ Empowerment Through Automation:\e[0m\n"
    printf "    %s\n" "Good tools don't just run commands; they handle the tedious details so you can focus"
    printf "    %s\n" "on your creation. This is a tool for getting things done."

    printf "\n"
    printf " \e[1;33m%s\e[0m\n" "What This Is, and What It Isn't"
    printf "  %s\n" "This is a hammer. A really, really good hammer for the specific nail of deploying full-stack"
    printf "  %s\n" "apps on a single VPS. It's for the freelancer, the indie hacker, the hobbyist. It is NOT an"
    printf "  %s\n" "enterprise-grade, multi-server, auto-scaling cluster manager. It's a tool for adults who"
    printf "  %s\n" "value simplicity, speed, and total control."
    pause
}


# --- Main Menu Loop ---
main() {
    while true; do
        show_logo
        printf "%s\n" "==================================================================================="
        printf "             \e[1;37m%s\e[0m\n" "KCStudio Launchpad V1.0"
        printf "           \e[90m%s\e[0m\n" "The Developer's Launch Platform"
        printf "%s\n" "==================================================================================="
        printf "\n"
        printf "  \e[36m[1] Prepare This Server For First Use\e[0m\n"
        printf "      \e[90m%s\e[0m\n" "(Run once on a fresh VPS to harden and prepare it)"
        printf "\n"
        printf "  \e[36m[2] Architect a New Full-Stack Project\e[0m\n"
        printf "      \e[90m%s\e[0m\n" "(Run for each new project you want to build)"
        printf "\n"
        printf "  \e[36m[3] Manage an Existing Project\e[0m\n"
        printf "      \e[90m%s\e[0m\n" "(Deploy code, view logs, backup a specific project)"
        printf "\n"
        printf "  \e[36m[4] Operate the Server\e[0m\n"
        printf "      \e[90m%s\e[0m\n" "(Check server health, manage swap, analyze traffic, etc.)"
        printf "\n"
        printf "%s\n" "-----------------------------------------------------------------------------------"
        printf "  \e[37m%s\e[0m      \e[37m%s\e[0m\n" "[D] Documentation & User Guides" "[Q] Quit"
        printf "%s\n" "==================================================================================="
        prompt "What do you want to do today? " main_choice

        case $main_choice in
            1) run_script "SecureCoreVPS-SetupV5.1.sh" ; pause ;;
            2) run_script "CreateProjectV9.3.sh" ; pause ;;
            3) run_script "ManageAppV4.3.sh" ; pause ;;
            4) run_script "ServerMaintenanceV1.2.sh" ; pause ;;
            [Dd]) show_docs_main ;;
            [Qq]) echo "Exiting." && exit 0 ;;
            *) warn "Invalid choice." ; pause ;;
        esac
    done
}

# --- Run Launch Animation Once ---
launch_kcstudio
verify_os
sleep 0.5
# pause  # Optional: pause to let the user admire the animation

# --- Execute Main ---
main
