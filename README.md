# TMonitor - Terminal Monitor for Multi-Pane Development Workflows

TMonitor is a lightweight shell-based utility to streamline your terminal-based development workflow using `tmux`. It allows you to define commands to run in separate panes and gives you a free interactive shell, all in one tmux session — perfect for managing logs, workers, build tools, and even SSH-based workflows.

---

## ✨ Motivation

In nearly every development scenario — whether you're building web apps, CLI tools, APIs, or background jobs — we constantly perform **repetitive terminal tasks**:

- Tailing logs
- Restarting queues or workers
- Running build tools (e.g., `npm`, `vite`, `php artisan`, `composer`)
- Navigating into project directories and managing subprocesses

Doing this manually every time eats up focus and time.

**TMonitor** was created to automate this routine with a single command.

It’s also incredibly useful for managing **remote SSH-based workflows**. Quickly spin up sessions on remote servers to monitor logs, debug services, or handle long-running workers — all within a structured `tmux` layout.

---

## ✅ Features

- Automatically creates a 4-pane `tmux` session:
  - 3 top panes run predefined commands (`CMD1`, `CMD2`, `CMD3`)
  - 1 bottom pane stays interactive (a free shell)

```
┌────────────┬────────────┬────────────┐
│  Pane 0    │  Pane 1    │  Pane 2    │
│  CMD1      │  CMD2      │  CMD3      │
├────────────┴────────────┴────────────┤
│               Pane 3                 │
│           Interactive Shell          │
└──────────────────────────────────────┘
```

- Easy reload with `Opt+R` (reloads commands)
- Exit safely with `Opt+Q` (asks for confirmation)
- Customizable via a simple `.conf` file
- Works with local and remote sessions via SSH

---

## 🧪 Tested On

- **macOS Sequoia**
- **tmux 3.5a**

---

## 🛠️ Installation

1. Clone or move the scripts to a permanent directory (recommended: `~/.tmux/scripts/`)
2. Make both scripts executable:

   ```bash
   chmod +x ~/.tmux/scripts/tmonitor.sh
   chmod +x ~/.tmux/scripts/reload_tmonitor.sh
   ```

3. Add this alias to your shell config (`.zshrc`, `.bashrc`, etc):

   ```bash
   alias tmonitor='~/.tmux/scripts/tmonitor.sh "$PWD"'
   ```

4. Reload your shell:

   ```bash
   source ~/.zshrc
   ```

---

## 📁 Project Structure

```
~/.tmux/scripts/
│
├── tmonitor.sh           # Starts the tmux session with custom panes
├── reload_tmonitor.sh    # Reloads the session and re-runs commands
```

---

## ⚙️ Configuration

In your project directory, create a `tmonitor.conf` file:

### Example: `tmonitor.conf`

```bash
SESSION_NAME="My Laravel App Monitor"

CMD1="tail -f storage/logs/laravel.log"
CMD2="composer dumpa && php artisan optimize:clear && npm run build && php artisan queue:work"
CMD3="php artisan command:run-custom-command"
```

- `SESSION_NAME` *(optional)*: Custom name for the tmux session
- `CMD1`, `CMD2`, `CMD3`: Commands to run in top panes

---

## 🚀 Usage

From your project root (where `tmonitor.conf` exists):

```bash
tmonitor
```

> This opens a tmux session with 4 panes: 3 running your custom commands, and a bottom pane ready for your input.

---

## 🔁 Hotkeys

Inside the tmux session:

- **Opt + Q** → Quit session (with confirmation)
- **Opt + R** → Reload commands (without restarting session)

---

## 🧭 Roadmap

Planned features to extend TMonitor:

- [ ] Support for custom layouts (e.g., vertical splits, grid)
- [ ] More than 3 command panes with dynamic layout
- [ ] Custom labels or titles for panes
- [ ] Integration with system stats (CPU, memory, disk)
- [ ] Persist pane state and session recovery

---

## 📌 Notes

- Ensure your `.conf` file exists and includes all required variables.
- Works well for **local development** and **remote SSH sessions**.
- Designed to minimize cognitive load and maximize focus during dev cycles.

---

## 🤝 Contributions

Feel free to fork, improve, or submit PRs. Ideas and feedback are always welcome!

---

## 📄 License

MIT
