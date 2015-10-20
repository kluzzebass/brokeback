# brokeback.pl

## Short backup script written in perl.

>Usage: `brokeback.pl [-v] [-r <generations to retain>] <backup destination> [<items to back up> ...]`
>
> * `-v`         - Be verbose
> * `-r <gen>`   - Cleanup the backup destination directory, and retain only `<gen>` number of backup generations.
>
>Example: `brokeback.pl -v /mnt/backupdisk /etc /home`
>
>...verbosely creates a backup of `/etc` and `/home`, and places the backup in `/mnt/backupdisk`.
>
>Example: `brokeback.pl -r 10 /mnt/backupdisk`
>
>...removes all but the last 10 backup generations from `/mnt/backupdisk`. Note: if the `-r` option is used, the script will exit after removing unwanted backup generations!

## How does it work?

Well, it turns out it works kinda like Apple's _Time Machine_ since _OS X Leopard_ or thereabouts. The script hard links files that haven't changed since the previous backup, which has the advantages of conserving space and at the same time making each backup generation appear like a full backup. (Time Machine also hard links directories, for further space savings, but I'm not about to dive down that rabbit hole.)

The script has only been tested on Linux, so YMMV.



