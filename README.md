# brokeback

## Short backup script written in perl.

>Usage: `brokeback.pl [-v] [-r <generations to retain>] <backup destination> [<items to back up> ...]`
>
> * `-v`         - Be verbose
> * `-r <gen>`   - Cleanup the backup destination directory, and retain only <gen> number of backup generations.
>
>Example: `brokeback.pl -v /mnt/backupdisk /etc /home`
>
>...verbosely creates a backup of `/etc` and `/home`, and places the backup in `/mnt/backupdisk`.
>
>Example: `brokeback.pl -r 10 /mnt/backupdisk`
>
>...removes all but the last 10 backup generations from `/mnt/backupdisk`. Note: if the `-r` option is used, the script will exit after removing unwanted backup generations!




