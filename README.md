
# Multi-Tor Rotating Proxy for Windows (PowerShell)

**Porting a Linux/Termux Tor IP rotation workflow into a Windows-native research tool**

<img width="1689" height="948" alt="image" src="https://github.com/user-attachments/assets/56de5bcc-8fbc-488a-a088-b696d25c899a" />


---

## ⚠️ Disclaimer

This project is intended **strictly for research, testing, and educational purposes**.

- This is **NOT a VPN**
- This does **NOT anonymize all system traffic**
- Only applications explicitly configured to use the proxy will route through Tor
- You are fully responsible for how you use this tool



## Overview

This repository provides a **single PowerShell script** that builds a **multi-instance Tor environment on Windows**, fronted by **Privoxy**, with automated **IP rotation** using Tor’s ControlPort.

The goal is to reproduce a Linux-based Tor IP rotation workflow **without WSL, Docker, or manual dependency setup**.

### What This Tool Does

✔ Launches multiple isolated Tor instances  
✔ Assigns unique SOCKS and Control ports per instance  
✔ Fronts all Tor instances with one HTTP proxy (Privoxy)  
✔ Rotates circuits using `SIGNAL NEWNYM`  
✔ Displays the active Tor exit IP  
✔ Automatically installs dependencies  
✔ Runs unattended after startup  

### What This Tool Does Not Do

✘ This is not a VPN  
✘ This does not capture OS-level traffic  
✘ This does not bypass Tor exit blocking  
✘ This does not guarantee anonymity  



## Architecture

```

[ Browser / Application ]
|
v
[ Privoxy :8118 ]
|
v
[ Tor SOCKS Instances ]
|     |     |     |
9050  9060  9070  9080  9090
|     |     |     |
Tor   Tor   Tor   Tor   Tor

```

Each Tor instance is fully isolated with its own data directory and control channel.



## Core Components

### Tor

- Provides anonymized network routing via relay circuits
- Each instance exposes:
  - SOCKS Port (traffic ingress)
  - Control Port (circuit management)
- Circuit rotation is triggered via `SIGNAL NEWNYM`

---

### Privoxy

- HTTP-to-SOCKS proxy
- Allows browsers and tools to use Tor without native SOCKS support
- Acts as a forwarding layer across multiple Tor instances

---

### ncat (Nmap)

- Lightweight TCP client
- Used to send raw commands to Tor ControlPorts
- Enables scripted circuit rotation

---

### PowerShell

- Orchestration and automation layer
- Handles:
  - Privilege escalation
  - Dependency installation
  - Process lifecycle
  - Configuration generation
  - Rotation scheduling



## System Requirements

| Requirement | Minimum |
|------------|---------|
| OS | Windows 10 / 11 |
| PowerShell | 5.1+ |
| Privileges | Administrator |
| Network | Outbound TCP allowed |
| Disk Space | ~200 MB |



## Dependencies (Auto-Installed)

The script automatically installs and manages:

- Tor
- Privoxy
- Nmap (for `ncat.exe`)
- Chocolatey (Windows package manager)

No manual installation is required.



## Execution Flow

1. Verifies Administrator privileges
2. Installs Chocolatey if missing
3. Installs or upgrades required packages
4. Detects executable paths dynamically
5. Terminates existing Tor/Privoxy processes
6. Recreates clean runtime directories
7. Launches multiple Tor instances
8. Generates Privoxy configuration
9. Starts Privoxy
10. Prompts for rotation interval
11. Enters infinite rotation loop:
    - Sends `SIGNAL NEWNYM`
    - Fetches current IP via proxy
    - Sleeps and repeats



## Runtime Directory Layout

```

%USERPROFILE%
├── .tor_multi
│   ├── tor0
│   ├── tor1
│   ├── tor2
│   ├── tor3
│   └── tor4
└── .privoxy
└── config

````

These directories are deleted and regenerated on each run.



## Network Ports Used

| Purpose | Port |
|------|------|
| Privoxy HTTP Proxy | 8118 |
| Tor SOCKS | 9050–9090 |
| Tor Control | 9051–9091 |

Ensure these ports are free before execution.



## How to Run

### Clone the Repository

```bash
git clone https://github.com/your-org/tor-ip-rotator-windows.git
cd tor-ip-rotator-windows
````

### Run the Script

```powershell
powershell -ExecutionPolicy Bypass -File .\IPHopper.ps1
```

You will be prompted to enter an IP rotation interval (minimum 5 seconds).

---

## Option 1: Browser Configuration

Set your browser’s HTTP proxy to:

```
Address: 127.0.0.1
Port:    8118
```

---

## Option 2: System-Wide Proxy (Computer-Level)

This enables the proxy **for the entire Windows operating system**, meaning **any application that respects system proxy settings** will route traffic through Privoxy → Tor.

### Enable System Proxy on Windows 10 / 11

1. Open **Settings**
2. Go to **Network & Internet**
3. Select **Proxy**
4. Under **Manual proxy setup**:
   - Enable **Use a proxy server**
   - Address: `127.0.0.1`
   - Port: `8118`
5. Click **Save**

Once enabled, Windows will route supported traffic through Tor automatically.

--- 
❗**Alternatively, you may enable the “Automatically detect settings” option directly**

---



## Important Notes About System-Wide Proxying

- ❗ **Not all applications honor system proxy settings**
  - Most browsers do
  - Some CLI tools do
  - Many games, updaters, and system services do not

- ❗ **DNS leakage is possible**
  - DNS queries may still go through the system resolver
  - This is normal unless DNS is explicitly proxied

- ❗ **Windows Update and system services may ignore the proxy**
  - This is expected behavior

- ❗ **This is still NOT a VPN**
  - Kernel-level traffic is untouched
  - Only proxy-aware applications are routed



## Disable System Proxy (Strongly Recommended After Use)

Leaving a system-wide proxy enabled can cause:
- Network slowness
- Application failures
- Confusing connectivity issues

To disable:

1. Go back to **Settings → Network & Internet → Proxy**
2. Turn **Use a proxy server** OFF
3. Save



## When to Use Each Mode

| Mode | Use Case |
|----|----|
| Browser-only | Testing, OSINT, research, safest |
| System-wide | Lab environments, controlled testing |

---

Verify routing by visiting:

```
https://api64.ipify.org
```

The displayed IP should match the script output.



## Expected Output

```
[+] Launching Tor nodes...
[+] Configuring Privoxy...
Enter IP rotation interval in seconds (min 5): 15
[+] New IP: 185.220.101.44
[+] Proxy: 127.0.0.1:8118
```

IP reuse may occur due to Tor exit node policies.



## Known Issues & Limitations

### IP Does Not Always Change

* Tor enforces circuit reuse
* Exit pool is limited

**Mitigation:** Increase rotation interval or instance count.

---

### Tor Exit Blocking

* Some services block Tor exits
* CAPTCHA and HTTP 403 responses are common

This is expected behavior.

---

### Antivirus Warnings

* Tor binaries are often flagged as suspicious

**Mitigation:** Whitelist if policy allows.

---

### Corporate or Restricted Networks

* Firewalls may block Tor or ControlPorts



## Common Errors

### `tor.exe not found`

* Chocolatey installation failed
* Executable path detection failed

**Fix:**

```powershell
choco list --local-only
```

---

### `Address already in use`

* Ports already bound by another process

**Fix:** Stop conflicting services or reboot.

---

### `Access denied`

* Script not run with Administrator privileges

**Fix:** Run PowerShell as Administrator.

<img width="980" height="377" alt="image" src="https://github.com/user-attachments/assets/c677b654-d783-424a-84a4-23f6b23229bf" />


## Customization

| Objective            | Location                       |
| -------------------- | ------------------------------ |
| Tor instance count   | `$socksPorts`, `$controlPorts` |
| Proxy port           | `$privoxyPort`                 |
| Rotation interval    | Runtime prompt                 |
| Binary paths         | `Find-Exe` fallback paths      |
| Disable auto-install | Remove Chocolatey section      |

---

## Intended Use Cases

* Privacy and security research
* OSINT lab environments
* Tor protocol experimentation
* Web application testing under Tor
* Teaching network anonymization concepts



## Final Notes

This project prioritizes:

* Transparency over abstraction
* Control over convenience
* Reproducibility over shortcuts

If you understand this system, you understand **Tor automation on Windows**.



## License

MIT License
Use responsibly.

```
```
