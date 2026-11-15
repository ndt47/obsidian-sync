# obsidian-sync

Obsidian Sync for the vault on deepend (`/mnt/deepend/library/obsidian`), run on **freeside** with Obsidian's official headless client ([`obsidian-headless`](https://obsidian.md/help/sync/headless), command `ob`). The iPhone and laptops run ordinary Obsidian with Sync. villa and the agents keep using the NFS share. This container is the bridge between the two.

It replaces the Self-hosted LiveSync services in the `apps` stack (`obsidian-couchdb`, `obsidian-bridge`, `notes.taylorplex.com`). Wiki: `wiki/research/Remote Vault Access.md`.

**Needs an active Obsidian Sync subscription.** The client itself is free.

## How it works
- `sync-loop.sh` runs a one-shot `ob sync` every `SYNC_INTERVAL` seconds (default 60). It deliberately doesn't use `ob sync --continuous`. Continuous mode only notices local changes through inotify, and on an NFS client inotify misses writes from other hosts. Each one-shot run rescans the vault against the state DB (adds, edits and deletes) and exits cleanly. Latency is up to about one interval in each direction.
- **Guards before every run.** `ob` treats a file that's missing locally as a local delete and pushes the delete to every device. So the loop refuses to sync when `wiki/Index.md` is missing, or when there are fewer than 50 files (an empty or failed mount).
- **Pause:** `touch /state/PAUSE` inside the container holds sync. `rm /state/PAUSE` resumes it.
- State lives in `/mnt/ssd/appdata/obsidian/headless`: the login token, the per-vault config with the derived E2E key, and the SQLite state DB. **Treat that directory as a secret.**
- It runs as `3018:3011` (the vault owner). It needs outbound network only: no ports, no Traefik.

## First-time setup
1. **On freeside (sudo):** `sudo install -d -o 3018 -g 3011 -m 0700 /mnt/ssd/appdata/obsidian/headless`
2. **Portainer → Stacks → Add stack → Repository:** `https://github.com/ndt47/obsidian-sync`, ref `refs/heads/main`, compose path `docker-compose.yml`, environment `local`. Deploy. Portainer pulls the image from GHCR (CI builds it; needs the `ghcr.io` registry credential). The log should show `not set up yet … waiting`.
3. **Hold the old sync:** stop `obsidian-bridge` in Portainer, so only one engine writes the vault during the cutover. Before the first sync, confirm there's a fresh ZFS snapshot of `deepend/library/obsidian` and make a local tarball (see Working with Nathan, *Snapshots*).
4. **Container console** (Portainer → `obsidian-sync` → Console, `/bin/sh`, or `sudo docker exec -it obsidian-sync sh`):
   ```sh
   touch /state/PAUSE                                  # hold the loop while setting up
   ob login                                            # email, password, 2FA
   ob sync-create-remote --name "Vault" --encryption end-to-end   # choose the E2E password; keep it in the password manager
   ob sync-setup --vault "Vault" --path /vault --device-name freeside-headless
   ob sync-config --path /vault --conflict-strategy merge \
       --file-types image,pdf,unsupported --configs "" --excluded-folders "inbox/claude"
   ob sync-status --path /vault
   ob sync --path /vault                               # first sync by hand: uploads the vault; watch it finish
   rm /state/PAUSE                                     # hand over to the loop
   ```
   `--configs ""` keeps `.obsidian/` (villa's desktop settings) out of Sync, so a phone's settings can't overwrite it. Each device keeps its own.
5. **iPhone / laptop:** install Obsidian, sign in, then *Settings → Sync → Remote vault → Connect* to "Vault" and enter the E2E password. **Remove or turn off the Self-hosted LiveSync plugin on that device first.**
6. **Canary:** on villa, write a note into the vault over NFS and confirm it reaches the phone within about a minute. Delete it and confirm it disappears. Then edit a note on the phone and confirm it shows up on NFS.
7. **Retire LiveSync** (separately, once the canary passes): remove the `obsidian-*` services and the `notes` route from the `apps` / `homeproxy` repos. Note that redeploying `apps` restarts the icloudpd containers that were stopped by hand on 2026-11-12.

## Operations
- Logs are quiet when nothing changes. Runs that move files print `Upload complete` / `Downloaded` / `Deleting` / `Merg…` lines.
- To upgrade, bump `OBSIDIAN_HEADLESS_VERSION` in the `Dockerfile` and push; CI publishes `ghcr.io/ndt47/obsidian-sync:sha-<commit>`. Then pin that tag in `docker-compose.yml`, push, and *Pull and redeploy*.
- **Never run desktop Obsidian Sync on a copy of this same folder.** Obsidian says to use one sync method per folder.
