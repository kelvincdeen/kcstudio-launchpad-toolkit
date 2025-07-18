<a href="https://kcstudio.nl">
  <img src="https://kcstudio.nl/img/KCstudio_Launchpad_Logo.webp" alt="KCStudio Launchpad Logo" width="300px">
</a>

# KCStudio Launchpad
> ### The fastest way to ship your whole portfolio.

A personal server butler that turns a blank VPS into a live, full-stack application in minutes. For all your projects.

No Docker. No Kubernetes. Just your server, your code, and one menu to run it all.

[![KCstudio Launchpad](https://img.shields.io/badge/Fresh%20VPS%20to%20Live%20Apps-In%205%20Min-yellow?style=for-the-badge)](https://launchpad.kcstudio.nl)

<p>
  <a href="LICENSE.md">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT">
  </a>
  <a href="https://github.com/KCstudio/KCstudio-launchpad-toolkit">
    <img src="https://img.shields.io/badge/Version-1.0.0-yellow.svg" alt="Version">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/Platform-Ubuntu%2024.04-orange.svg" alt="Platform">
  </a>
</p>

<a href="https://launchpad.kcstudio.nl">
  <img src="https://kcstudio.nl/github/main_menu_startup.gif" alt="KCStudio Launchpad Main Menu Startup Animation">
</a>

---

> **TL;DR:** KCStudio Launchpad is your personal server butler. It's a command-line toolkit that automates the deployment and management of full-stack applications for solo developers, turning a single server into a secure, multi-project portfolio hub.

---

### See It In Action

This isn't just a concept; it's a real, working system. The entire demo platform was deployed and is managed by the Launchpad toolkit itself.

## [launchpad.kcstudio.nl](https://launchpad.kcstudio.nl/)

*   🌐 **Live Demo:** [launchpad.kcstudio.nl/backend-tester](https://launchpad.kcstudio.nl/backend-tester)
*   📚 **Live API Docs:** [launchpad.kcstudio.nl/api-docs](https://launchpad.kcstudio.nl/api-docs)
*   🎥 **Full Video Walkthrough:** [Watch the 5-minute setup](https://launchpad.kcstudio.nl/the-why)

---

### What a created project looks like (check out the files in this repo: [showcase-project](https://github.com/kelvincdeen/kcstudio-launchpad-toolkit-showcase) ):

```
[+] Displaying directory tree for 'showcase-launchpad' (max depth: 3, ignoring venv):
/var/www/showcase-launchpad
├── app
│   ├── __pycache__
│   │   ├── helpers.cpython-312.pyc
│   │   └── main.cpython-312.pyc
│   ├── helpers.py
│   ├── main.py
│   └── requirements.txt
├── auth
│   ├── __pycache__
│   │   ├── helpers.cpython-312.pyc
│   │   └── main.cpython-312.pyc
│   ├── email_template.html
│   ├── helpers.py
│   ├── main.py
│   ├── requirements.txt
│   └── users.db
├── database
│   ├── __pycache__
│   │   ├── helpers.cpython-312.pyc
│   │   └── main.cpython-312.pyc
│   ├── data.db
│   ├── helpers.py
│   ├── main.py
│   └── requirements.txt
├── logs
│   ├── app
│   │   └── output.log
│   ├── auth
│   │   └── output.log
│   ├── database
│   │   └── output.log
│   └── storage
│       └── output.log
├── project.conf
├── storage
│   ├── __pycache__
│   │   ├── helpers.cpython-312.pyc
│   │   └── main.cpython-312.pyc
│   ├── files
│   ├── helpers.py
│   ├── main.py
│   ├── requirements.txt
│   └── storage.db
└── website
    └── index.html
```

---

### My Story.

> I've always been **a builder**, driven to turn ideas **into real things**. CAD designs, 3D printing, ESP32 projects. My goal is always to create that **"it just works" feeling**. And most of all, polish it the best I can with the time I have.
>
> When I turned to **web apps**, I hit the same **wall probably everyone does**: confusing, frustrating server setups. A few weeks ago, I bought my first VPS. I wasn't a **sysadmin**; I'd never even configured an NGINX file. **After struggling** to get one app online, I was convinced there had to be **a better way** than handing my soul over to Vercel or some other BaaS.
>
> Then, thank god for a vacation, I got a little **sidetracked**.
>
> For two weeks, **fueled by coffee**, I obsessed over a single idea: what if I could **automate away the fear?** I architected the ideal workflow first. The safety features, the **"easy buttons"**, everything I could think of needing. Then used AI as my expert collaborator to generate and relentlessly **refine** the code. I didn't just want it to work; I wanted it to be **solid**, secure, and built on best practices I was still learning.

This toolkit is the result of that obsession, and I honestly can't live without it anymore.
  
> **My learning journey, codified.**

---

### What it *feels* like to use?

This isn't about features; it's about flow. It's about speed.

> **Got a new project finished?** It's live in minutes. Zip your `dist` folder, deploy from a URL, and you're online. I find it even easier than GitHub Pages.

> **Need to test an idea?** Hit a few keys to edit your `main.py` file. The moment you save, the toolkit asks if you want to restart the service. Your changes are live instantly.

> **Something not working?** No problem. Hit a few more keys to view the live, streaming logs for that specific service and see exactly what's wrong.

> **Need a new Python package?** Jump directly into an app's isolated `venv`, `pip install` what you need, and you're done. All from a simple menu.

---

### 🚀 The Complete, Production-Ready Toolbox

The Launchpad is a guided journey. It's not just a collection of scripts; it's a logical, four-step path from a blank server to a portfolio of managed applications.

#### `1.` ✅ Secure the Foundation (`SecureCoreVPS-Setup`)
*Run this once on a fresh server to put it into a hardenend state.*

*    **Secure SSH:** Forces key-only login, **disables password & root auth entirely**, moves SSH to a custom port, and enforces modern encryption ciphers.
*    **Automated Intrusion Defense:** Installs and configures `ufw` (firewall) to only allow SSH and Nginx Full ports and `fail2ban` to automatically ban brute-force attackers.
*    **Hardened Web Server:** Sets up NGINX with secure global settings and a "black hole" default to prevent IP snooping and info leaks.
*    **Always-On Security:** Enables `unattended-upgrades` to automatically install critical OS security patches.
*    **Full Security Audit:** Finishes with a `lynis` scan to prove the server's hardened state.

<a href="https://launchpad.kcstudio.nl">
  <img src="https://kcstudio.nl/github/setup.png" alt="KCStudio Launchpad Create Project" >
</a>

#### `2.` ✅ Architect the Apps (`CreateProject`)
*This is the architect. It doesn't just configure your server; it **writes a huge amount of high-quality, secure backend code for you.** Pick components, type in your domains, and it builds the rest, with proper rollback cleanup if anything goes wrong.*

*    **Modular Backend Architect:** Choose your components: 
     * a modern **`auth`** service with magic links (via Resend) and rich profiles; 
     * a powerful **`database`** API with full CRUD and a hybrid JSON schema; 
     * a secure **`storage`** API for file authenticated uploads, with public unguessable URLs; 
     * a custom **`app`** canvas for your business logic with examples for public, auth and admin endpoints. They all work together, or on their own.
*    **Built-in API Protection:** All generated APIs come with sensible rate limiting and CORS middleware configured out of the box.
*    **Rock-Solid Infrastructure:** Automatically builds everything on a secure foundation, with isolated system users, `systemd` services for auto-restarts, and full NGINX proxying with SSL for your custom domains.

<a href="https://launchpad.kcstudio.nl">
  <img src="https://kcstudio.nl/github/create.png" alt="KCStudio Launchpad Create Project" >
</a>

#### `3.` ✅ Manage your Projects (`ManageApp`)
*Your day-to-day command center for a specific project. Select a project, and get to work.*

*    **Headache-Free Deployments:** Update your apps from a local path or directly from a URL (like a GitHub .zip), with safe previews before you commit.
*    **Instant Diagnostics & Debugging:** Stream live logs, run full-stack health checks, or jump directly into an application's isolated, venv-activated shell.
*    **Secure Data & Secret Management:** Create safe backups of your code or databases, explore your data with an interactive CLI (`litecli`), rotate JWT keys, and securely edit `.env` files.
*    **Find & Edit Any Backend File:** Use a fuzzy-finder (`fzf`) to instantly open and edit any file in your projects, right from the menu. Perfect for quick fixes.
*    **The "Big Red Button":** A secure `DELETE` function that completely and cleanly removes every trace of a project from the server.

<a href="https://launchpad.kcstudio.nl">
  <img src="https://kcstudio.nl/github/manage.png" alt="KCStudio Launchpad Create Project" >
</a>

#### `4.` ✅ Operate the Server (`ServerMaintenance`)
*A "Swiss Army Knife" to monitor server health, analyze performance, and use powerful utilities.*

*    **Interactive Real-Time Dashboards:** Launch `htop` to see what's eating your CPU/RAM or `ncdu` to find out what's taking up disk space.
*    **Visual File & Service Management:** Browse the entire filesystem with a GUI-like file browser (`mc`) or manage any `systemd` service with a searchable, interactive menu.
*    **One-Command Security & Traffic Audits:** Generate a beautiful HTML traffic report (`GoAccess`), check firewall and SSH logs directly, or re-run a full `lynis` security audit.
*    **Powerful Server-Wide Utilities:** Explore any SQLite database on the server, add cron jobs with a step-by-step wizard, manage SSL certificates, or configure a SWAP file.

<a href="https://launchpad.kcstudio.nl">
  <img src="https://kcstudio.nl/github/maintenance.png" alt="KCStudio Launchpad Create Project" >
</a>

---

### 🚀 Quick Start

Paste this command into a fresh **Ubuntu 24.04** server, logged in as `root`.

```bash
git clone https://github.com/kelvincdeen/KCstudio-launchpad-toolkit.git /opt/kcstudio-launchpad-toolkit && \
chmod +x /opt/kcstudio-launchpad-toolkit/KCstudioLaunchpadV1.0.sh && \
sudo /opt/kcstudio-launchpad-toolkit/KCstudioLaunchpadV1.0.sh
```
The butler will take over and guide you the rest of the way. After this initial setup, you can run the main menu at any time with the `launchpad` command (if you create the alias) or by running `sudo /opt/kcstudio-launchpad-toolkit/KCstudioLaunchpadV1.0.sh`.

---

## ❓Frequently Asked Questions
  
  *   **Is it really free?**
      *   Yes. 100%. It's released under the MIT License. Fork it, change it. Can't wait to see what you will do with it! :)
  *   **Do I still need to learn about security and server management?**
      *   **Yes, absolutely.** Think of this toolkit as your co-pilot, not autopilot. It automates away about 95% of the initial complexity and provides a secure starting point, but you are still the driver. The internet is a wild place, and security is a continuous process. This tool handles the tedious "how" so you can spend your time learning the crucial "why."
  *   **How many projects can I run with this?**
      *   As many as your VPS can handle. Each project is fully isolated with its own system user, services, domain, and SSL certificate.
  *   **What are the requirements?**
      *   A fresh Ubuntu 24.04 VPS from any provider (Hetzner, DigitalOcean, Linode etc.) and a public SSH key on your local machine. That's it. (and a domain pointed to your server ofcourse)
  *   **Why not Docker?**
      *   It's a deliberate choice. For a solo developer, Docker can be a heavy, abstract layer you don't always need. This toolkit uses the tools your server already understands. This is about owning your stack, top to bottom.
  *   **What API framework does it use? And what's up with the endpoint names?**
      *   All the backend APIs are built with **FastAPI**. It's super fast and easy to work with. I prioritized what felt most straightforward for someone (like me!) who just wants to get things working without getting tangled in textbook definitions. You get clear, working APIs right out of the box.
  *   **What This Is, and What It Isn't**
      *   This is a hammer. A really, really good hammer for the specific nail of deploying multiple isolated full-stack apps on a single VPS. It's designed to turn that single server into a powerful host for your entire portfolio. It's for the freelancer, the indie hacker, the hobbyist. It is NOT an enterprise-grade, multi-server, auto-scaling cluster manager. It's a tool for you who value simplicity, speed, and total control over their entire stack of applications.


---

### 🤝 Contributing

Pull requests are welcome! If you find a bug, have a security improvement, or want to enhance the CLI user experience, feel free to open an issue or submit a PR. This is a learning-focused toolkit, so clear, readable code is always prioritized (for the most part).

See Future Roadmap to see whats on my mind regarding improving and updating the toolkit.

### ❤️ Like this project?

If this toolkit saves you a weekend of headaches, here's how you can say thanks:

*   ⭐ **Star the repo** on GitHub - it's the best way to help others discover it.
*   💬 **Share it with a friend** or a community who would find it useful.
*   ☕ **[Buy me a coffee](https://buymeacoffee.com/kcstudio)** to fuel future development.

---

### My Studio

This toolkit is a demonstration of the holistic, product-focused approach I apply to my work. If you need a high-end website, web application, or custom IoT/electronics solution, **[visit my studio at KCstudio.nl](https://kcstudio.nl)** to see what I do for a living.

---

### 🗺️ Future Roadmap

I have a few things in mind on how I could improve the toolkit, but for now...it just works so I am happy!
