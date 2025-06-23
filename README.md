# Plex 2 setup

---

Plex 2 is the development name for the next-generation depoyment of
my home media server and its supporting systems. It is so named because
I already have an in-use deployment of plex, which I intend to maintain
during development.

# High level design

## Components

* Plex - Media server application, content metadata.
* Lidarr - Music collection auto-downloader                              (port 8686)
* Radarr - Movie collection auto-downloader                              (port 7878)
* Readarr - Book collection auto-downloader                              (port 8787)
* Sonarr - TV collection auto-downloader                                 (port 8989)
* Bazarr - Subtitle auto-downloader                                      (port 6767)
* Prowlarr - Central indexer, supporting Lidarr, Radar, Readarr, Sonarr  (port 9696)
* Oversearr - Media requester UI                                         (port 5055)
* qBittorrent - Bittorrent client                                        (port 3489)

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

* Plex will run as `plex`.
* \*arr apps will run as `arr`.
* transmission will run as `transmission`.
* Both `plex`, `arr`, and `transmission` are in `plexapp` group.
* Server management user is also in `plexapp` group.

## Secrets

Secrets are stored in `.env.bash` file. A template is provided in `.env.bash.template`.

# Details

## Networking

* The torrent client is run in the `seedbox` network namespace. 
  This namespace sends all traffic through a Wireguard tunnel to the seedbox.
* Plex and arrs remains on the default namespace, and is exposed via existing 
  reverse-proxy
* This is configured by the `set-up-wg-ns.sh` script, with either `up` or 
  `down` args.

To test running something from the network namespace:

```bash
sudo ./set-up-wg-ns.sh up`
sudo ip netns exec seedbox ping google.com -c 1
```

## Storage

* All data is stored on my Synology NAS, mounted via Samba.
* Application configs are not on the NAS-mounted drive, because they contain
  SQLite DBs, and don't tend to work well with NAS mounts because they don't 
  support file locking properly.
* Mounted as `plex:plexapp`
* All data is on one filesystem so that hardlinks can be used to enable
  atomic moves and deduplication.
* During development, 

### Directory Structure

* Torrent client gets access to `data/torrents`.
* \*arrs gets access to `data` because they need access to `torrents`, and move 
  things to `media`.
* Plex and media servers gets access to `data/media`.

```
plex_data_mnt/plex2/data/
├── torrents
│   ├── books
│   ├── movies
│   ├── music
│   └── tv
└── media
    ├── books
    ├── movies
    ├── music
    └── tv
```

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
one of which mounts the samba share. For me, I want to mount it to 
`/home/user/plex2/plex_data_mnt`, so it creates a 
`home-user-plex2-plex_data_mnt.mount` unit. This is then installed into 
`/etc/systemd/system/`.

## Torrent client (qBittorrent)

* qBittorrent is the torrent client.
* It is run as `transmission:plexapp`.
* It is run using the `arrs` systemd service in the arrs compose file 
  `arrs-compose/docker-compose-arrs.yml`.
* Set a WebUI password on first use. The temporary password is printed in 
  the logs on first startup.
* You must configure a proxy. My seedbox provider has a HTTP proxy service, 
  which I configure in the qBittorrent webUI.
* WebUI is available on port 3489.

# Progress

* plex2 NAS mounting has migrated from sshfs -> SMB [DONE]
* plex2 users `plex` and `arr` as well as `plexapp` group created [DONE]
* plex2 running under `plex:plexapp`, replacing old plex deployment [DONE]
* NAS mounted as `nobody:plexapp` [WON'T DO: plex doesn't like it...]
* plex config now on non-NAS mount to avoid file locking issues [DONE]
* Set up seedbox network namespace [DONE]
* Run transmission in `seedbox` network namespace [WON'T DO: easier to run qBT with HTTP proxy]
* Run arrs in seedbox network namespace [WON'T DO: arrs don't need to be proxied]
* Run qBittorrent with HTTP proxy [DONE]
* Run arrs & qBT in docker-compose [DONE]
