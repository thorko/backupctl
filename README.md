# backupctl
Backup your linux distro with rsync

### Install
#### create your configs in /etc/backup
```
sudo mkdir -p /etc/backup
sudo cp conf/sources.conf /etc/backup/
sudo cp conf/backup.conf /etc/backup/
sudo cp conf/excludes.conf /etc/backup/
```

edit your config files and make sure
you can connect via ssh to your backup server

### Run
./backupctl.pl -c /etc/backup/backup.conf -d
