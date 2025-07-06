# NMAP FIRING RANGE – CONTRIBUTING

Part of the **Nmap Firing Range** project  
GitHub: [https://github.com/unspecific/nmap-firing-range](https://github.com/unspecific/nmap-firing-range)  
Author: Lee "MadHat" Heath (@unspecific)  
License: Apache 2.0

---

## 🤝 How to Contribute

Contributions are welcome—but don’t half-ass it.

If you're adding a new service, fixing a bug, or improving the UI, make sure it works, is clean, and doesn’t break the randomized logic or scoring flow.

---

## 📦 Adding a New Service

1. **Create a new folder** under `services/` with your emulator or script.
2. Include a `run.sh` or equivalent that:
   - Reads `$USERNAME`, `$PASSWORD`, `$FLAG`
   - Binds to the defined port or uses the injected random one
   - Logs meaningful actions (optional but appreciated)
3. Add your service to the `launch_lab` config or rotation logic (if randomized).

Make sure it:
- Starts cleanly in Docker
- Can be detected via Nmap
- Isn’t just another echo server in disguise

---

## 🧪 Testing

Use the existing `launch_lab` and `check_lab.sh` scripts to verify:
- The lab launches without errors
- Flags are generated, captured, and scored
- Logs are shipped correctly (if applicable)

Don’t submit broken labs unless you're asking for help fixing it—mark those clearly in your PR.

---

## 🛠️ Submitting Pull Requests

1. Fork the repo.
2. Create a branch (`feature/cool-new-service`, not `patch-1`).
3. Commit clearly.
4. Open a PR with a **real description**. “Fixes” or “update” won’t cut it.
5. Tag @unspecific if you want eyes on it faster.

---

## 🚫 Things That Will Get Ignored

- Services with hardcoded credentials
- Unreadable code, especially without comments
- “I ran this once and it kinda worked” level commits
- Stuff that breaks randomness or logs noise without value

---

## 🙏 Thanks

This project started as a learning tool, and it stays useful because people like you push it forward. If you want to collaborate beyond a PR, reach out on GitHub or Twitter (@unspecific).

Now go break something. On purpose.

