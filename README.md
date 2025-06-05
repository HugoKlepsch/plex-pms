# Samba credentials 

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

# Systemd mount using CIFS

File, where `home-user-plex-plex_data_mnt` refers to `/home/user/plex/plex_data_mnt`:

```bash
sudo vim /etc/systemd/system/home-user-plex-plex_data_mnt.mount
```

Contents:

```
[Unit]
Description=Mount SMB Share
After=network-online.target
Wants=network-online.target

[Mount]
What=//<hostname or ip>/<share>
Where=/path/to/where/it/goes
Type=cifs
# Get UID and GID using `id` for the user to mount as
Options=credentials=/etc/samba/creds_plex_data,uid=1000,gid=1000,iocharset=utf8,nofail
TimeoutSec=30

[Install]
WantedBy=multi-user.target
```
