# Plex can't play a torrented file until the torrent is stopped

## Symptom

After a torrent finishes downloading, Plex fails to play the file with:

```
Error code: s1001 (Network)
```

Plex server log shows ffmpeg media analysis failing:

```
[Req#…/Transcode] MDE: video has neither a video stream nor an audio stream
[Req#…/Transcode] Streaming Resource: Cannot make a decision because either
the file is unplayable or the client provided bad data
```

Clicking "stop" on the (already 100%-complete, seeding) torrent in qBittorrent
immediately fixes playback. Files play fine when the SMB share is mounted on
a separate machine; the issue historically did not occur when Plex ran on a
different host than qBittorrent.

## Setup

- server (Debian 13, kernel 6.12) runs all containers.
- Storage is a Synology NAS at `192.168.50.3` exporting `\\192.168.50.3\plex_data` over SMB.
- The host mounts the share once at `/home/hugo/plex/plex_data_mnt`; every
  container (Plex, qBittorrent, *arrs) bind-mounts subpaths of it. So they
  all share a single kernel CIFS client.
- Radarr uses hardlinks: the same inode appears at both
  `…/torrents/movies/<Release>/<file>.mkv` (qBittorrent's path) and
  `…/media/movies/<Title>/<file>.mkv` (Plex's path).

Mount options in effect: `vers=3.1.1,cache=strict,nobrl,reparse=nfs,…`.

## Diagnosis

`stat` and `open(O_PATH)` succeed via both paths and report identical inode
and size — they are real hardlinks. But `open(O_RDONLY)` returns **EINVAL**
*only* via the `media/` path while qBittorrent has a handle on the
`torrents/` path:

| State               | open via torrents/ | open via media/ |
|---------------------|--------------------|-----------------|
| qBittorrent seeding | OK                 | EINVAL          |
| Torrent stopped     | OK                 | OK              |

`/proc/fs/cifs/open_files` confirmed a single SMB handle held against the
torrents-path filename. A tcpdump of the failing `os.open` captured the
SMB2 CREATE response from Synology:

```
NTSTATUS 0xc000000d  (STATUS_INVALID_PARAMETER)
```

which the kernel translates to EINVAL.

## Root cause

With `cache=strict`, the Linux CIFS client requests SMB2 leases keyed by
inode for every open. qBittorrent's open of path A holds an exclusive lease
on that inode at the Synology Samba server. When Plex (same kernel CIFS
client → same `ClientGUID` → same per-inode lease key) issues a CREATE for
the alternate hardlink path B, the server rejects it with
`STATUS_INVALID_PARAMETER`.

When Plex previously ran on a separate host, it presented a different
`ClientGUID`; the server treated it as an independent peer, broke the
existing lease, and granted a fresh handle — so the bug was hidden.

## Fix

Add `nolease` to the CIFS mount options. The kernel exposes it as a
supported flag (`/proc/fs/cifs/mount_params` lists `nolease:flag`) and it
stops the CIFS client from requesting leases, which eliminates the
inode-keyed lease collision without any server-side changes.