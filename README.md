# Plex 2 setup

---

Plex 2 is the development name for the next-generation depoyment of
my home media server and its supporting systems. It is so named because
I already have an in-use deployment of plex, which I intend to maintain
during development.

# High level design

## Components

* Plex - Media server application, content metadata.
* Lidarr - Music collection auto-downloader
* Radarr - Movie collection auto-downloader
* Readarr - Book collection auto-downloader
* Sonarr - TV collection auto-downloader
* Bazarr - Subtitle auto-downloader
* Prowlarr - Central indexer, supporting Lidarr, Radar, Readarr, Sonarr
* Oversearr - Media requester UI
* TBD - Bittorrent client

Components are run as docker containers, started with docker-compose,
service lifecycle managed by Systemd unit files. Configuration and secrets
are stored in `.env` files.

## How they work together

Movie example:

1. User makes a request in Overseerr for a movie.
2. Overseerr tells Radarr to add the movie.
3. Radarr asks Prowlarr to search for it across configured indexers.
4. Prowlarr finds it and returns the best match.
5. Radarr sends it to torrent client (qBittorrent, NZBGet, etc.).
6. Once downloaded, Radarr renames and moves it into media library.
7. Plex picks it up and it becomes available for viewing.

## Permissions

* Plex will run as `plex` and \*arr apps will run as `arr`.
* Both `plex` and `arr` are in `plexapp` group.
* Server management user is also in `plexapp` group.

## Storage

* All data is stored on my Synology NAS, mounted via Samba.
* Application configs are not on the NAS-mounted drive, because they contain
SQLite DBs, and don't tend to work well with NAS mounts because they don't 
support file locking properly.
* Mounted as `plex:plexapp`
* All data is on one filesystem so that hardlinks can be used to enable
  atomic moves and deduplication.
* During development, 

# Details

## Data mounts

### Samba credentials 

Create a credentials file here:

```bash
sudo vim /etc/samba/creds_plex_data 
```

In it, we have something like this:

```
username=foo
password=bar
```

Note: no quotation marks needed. If you need it, `domain` can also be added.

Protect it:

```bash
sudo chmod 600 /etc/samba/creds_plex_data
```

### Systemd mount using CIFS


The `create-systemd-service.sh` script will generate a set of systemd units, 
one of which mounts the samba share. For me, I want to mount it to `/home/user/plex2/plex_data_mnt`,
so it creates a `home-user-plex2-plex_data_mnt.mount` unit. This is then installed into `/etc/systemd/system/`.

# Progress

* plex2 NAS mounting has migrated from sshfs -> SMB [DONE]
* plex2 users `plex` and `arr` as well as `plexapp` group created [DONE]
* plex2 running under `plex:plexapp`, replacing old plex deployment [DONE]
* NAS mounted as `nobody:plexapp` [WON'T DO: plex doesn't like it...]
* Arrs... [TODO]
