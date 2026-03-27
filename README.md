# mac-cache-cleaner

A simple, safe bash script to clear common macOS caches and free up disk space.

> **Disclaimer:** This script is provided "as-is", without warranty of any kind, express or implied. The author makes no guarantees about its fitness for any particular purpose. You are solely responsible for reviewing the script and understanding what it does before running it. The author accepts no liability for data loss, system instability, application misbehaviour, or any other damages arising from the use of this script. Use at your own risk.

---

## What it clears

| Target | How |
|---|---|
| `~/Library/Caches` | App caches — rebuilt automatically on next launch |
| `~/Library/Logs` | App log files |
| `~/.cache` | XDG cache directory |
| npm cache | `npm cache clean --force` *(if npm is installed)* |
| Homebrew cache | `brew cleanup --prune=all` *(if brew is installed)* |
| pip cache | `pip3 cache purge` *(if pip3 is installed)* |
| DNS cache | `dscacheutil` + `mDNSResponder` restart *(requires sudo)* |

With `--sudo`, also clears:

| Target | Notes |
|---|---|
| `/Library/Caches` | System-level app caches |
| `/Library/Logs` | System-level logs |

npm, Homebrew, and pip steps are automatically skipped if those tools are not installed on your machine.

---

## Requirements

- macOS (tested on Sequoia 15.x, Apple Silicon)
- bash 3.2+ (ships with every Mac)
- No dependencies — uses only built-in macOS tools

---

## Usage

```bash
# Make it executable (one time)
chmod +x clear-cache.sh

# Preview what would be deleted — nothing is touched
./clear-cache.sh --dry-run

# Clear user-level caches
./clear-cache.sh

# Clear user + system caches (requires sudo password)
./clear-cache.sh --sudo

# Combine flags
./clear-cache.sh --dry-run --sudo
```

---

## Safety

- **Always run `--dry-run` first** to see exactly what will be deleted on your machine before committing.
- The script uses an explicit whitelist of allowed deletion targets. Any path not on the whitelist causes an immediate abort — there is no way for a bug or future edit to accidentally delete outside of the intended directories.
- All deletions use `find -mindepth 1`, which clears the *contents* of each directory but never the directory itself.
- `$HOME` is validated at startup — the script refuses to run if it is unset, empty, or set to `/`.
- macOS will automatically rebuild all cleared caches on next use. First app launches after clearing may be slightly slower than usual.

### What NOT to expect

- This script does **not** touch `~/Documents`, `~/Desktop`, `~/Downloads`, or any other user data.
- It does **not** clear browser data, saved passwords, cookies, or app preferences.
- It does **not** uninstall applications or packages.
- Running `--sudo` clears `/Library/Caches` and `/Library/Logs`. It does **not** touch `/System`, `/usr`, or any other protected system directory.

---

## Tested on

| Machine | macOS | Result |
|---|---|---|
| MacBook Pro (Apple Silicon) | Sequoia 15.x | ~25 GB freed |

This has been tested on one machine. It may behave differently on your setup depending on which tools are installed, macOS version, or system configuration. **Always use `--dry-run` first.**

---

## Contributing

Bug reports and pull requests are welcome. Please open an issue before submitting a large change.

---

## License

MIT — see [LICENSE](LICENSE).
