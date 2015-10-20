#!/usr/bin/perl -w

# Brokeback - Gaily Protecting Your Data

# (C) 2008-2015 - Jan Fredrik Leversund <kluzz@radical.org>

# History
#
# 1.2 - Minor tweaks in preparation for github.
# 1.1 - Added retention code
# 1.0 - Initial release
#


use File::stat;
use Fcntl ':mode';
use File::Path;
use File::Copy;
use Lchown qw(lchown LCHOWN_AVAILABLE);
use Time::localtime;
use POSIX qw{strftime mkfifo};
use Unix::Mknod qw(:all);
use Getopt::Std;
use Data::Dumper;
use File::Glob ':globally';

sub blag;

$ZERO_BACKUP_DIR = "ZERO_BACKUP";
$SKIP_FILE = ".NOBACKUP";
$LOG_FILE_SUFFIX = "log";
%STATS = (
	'created_dirs' => 0,
	'copied_files' => 0,
	'created_nodes' => 0,
	'created_fifos' => 0,
	'created_symlinks' => 0,
	'created_hardlinks' => 0,
	'copied_bytes' => 0,
	'unknown_items' => 0
);

%opts = ();
getopts("vr:", \%opts);

$VERBOSE = defined $opts{'v'} || 0;
$RETENT = defined $opts{'r'} ? $opts{'r'} : 0;



$backup_start_time = time;
$START_TIME = localtime($backup_start_time);

die "Usage: $0 [-v] [-r <generations to retain>] <backup destination> [<items to back up> ...]\n"
	unless $RETENT || scalar @ARGV > 1;

die "Backup destination directory not found or not writable.\n"
	unless -d $ARGV[0] && -w $ARGV[0];

warn "Warning: This system lacks the lchown() system call. Expect unexpected results.\n"
	unless LCHOWN_AVAILABLE;

# The backup destination directory.
$BACKUP_DEST = shift @ARGV;




# THIS SECTION FOR RETENTION

if ($RETENT)
{
	warn "Retaining $RETENT generations in backup directory $BACKUP_DEST.\n";
	@list = sort grep { -d } <$BACKUP_DEST/*>;
	eval { splice @list, -$RETENT; };
	exit if $@ || scalar @list == 0;

	for $dir (@list)
	{
		rmtree("$dir");
		unlink("$dir.log");
	}
	exit;	
}


# THIS SECTION FOR BACKUP


# The list of items to back up.
%BACKUP_ITEMS = ();
$BACKUP_ITEMS{shift @ARGV} = 1 while scalar @ARGV;
	

# The base name for the current backup run
$BASE_NAME = strftime("backup_%Y%m%d_%H%M%S", $START_TIME->sec(), $START_TIME->min(), $START_TIME->hour(),
	$START_TIME->mday(), $START_TIME->mon(), $START_TIME->year());

$PREV_BASE_NAME = find_previous_backup();

open LOGFILE, ">$BACKUP_DEST/$BASE_NAME.$LOG_FILE_SUFFIX" or die "Unable to open logfile: $!\n";
blag "Starting backup.";

# Loop through each backup item
foreach my $item (sort keys %BACKUP_ITEMS)
{
	my $devstat = lstat($item);
	backup_item($item, $devstat->dev()) if defined $devstat;
}

$duration = time() - $backup_start_time;
$hours = int($duration / 3600);
$minutes = int($duration / 60) % 60;
$seconds = $duration % 60;

blag "Statistics:";
blag " Created directories:  " . $STATS{'created_dirs'};
blag " Created nodes:        " . $STATS{'created_nodes'};
blag " Created fifos:        " . $STATS{'created_fifos'};
blag " Created symlinks:     " . $STATS{'created_symlinks'};
blag " Created hardlinks:    " . $STATS{'created_hardlinks'};
blag " Copied files:         " . $STATS{'copied_files'};
blag " Copied bytes:         " . $STATS{'copied_bytes'};
blag " Bytes copied pr. sec: " . ($STATS{'copied_bytes'} / ($duration ? $duration : 1));
blag " Unknown items found:  " . $STATS{'unknown_items'};

blag sprintf("Backup completed in %d hour%s, %d minute%s, %d second%s.", $hours, $hours != 1 ? 's' : '', $minutes, $minutes != 1 ? 's' : '', $seconds, $seconds != 1 ? 's' : '');

# Remove the temporary dummy backup directory.
rmtree "$BACKUP_DEST/$ZERO_BACKUP_DIR" if -e "$BACKUP_DEST/$ZERO_BACKUP_DIR";

# Exit.

# Recursive subroutine for backing a single item.
sub backup_item
{
	my $item = shift;
	my $dev = shift;
	my $st = lstat($item);

	unless (defined $st)
	{
		blag "Item not found: " . strim($item);
		return;
	}
	
	if (S_ISDIR($st->mode()))
	{
		blag "Creating directory: " . strim("$BACKUP_DEST/$BASE_NAME/$item");
		eval { mkpath "$BACKUP_DEST/$BASE_NAME/$item"; };
		$STATS{'created_dirs'}++;

		if ($st->dev() != $dev)
		{
			blag "Item is on different file system, skipping: " . strim($item);
			return;
		}

		if (-e "$item/$SKIP_FILE")
		{
			blag "Skip file detected, skipping: " . strim($item);
			return;
		}

		if (opendir DIR, $item)
		{
			my @items = readdir DIR;
			closedir DIR; # Don't wanna run out of file handles
			
			foreach my $next_item (@items)
			{
				backup_item("$item/$next_item", $dev) unless $next_item eq '.' || $next_item eq '..';
			}
			
			# Set the directory modes after the directory has been processed.
			chown $st->uid(), $st->gid(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change ownership: $!";
			chmod $st->mode(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change mode: $!";
			utime $st->atime(), $st->mtime(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to update access and modification times: $!";
		}
		else
		{
			blag "Unable to open item: " . strim($item), "Error: $!";
		}
		return;
	}

	# Symlink
	if (S_ISLNK($st->mode()))
	{
		blag "Symlinking: " . strim($item);
		symlink(readlink($item), "$BACKUP_DEST/$BASE_NAME/$item") or blag "Unable to create symlink: $!";
		lchown $st->uid(), $st->gid(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change ownership: $!";
		$STATS{'created_symlinks'}++;
		return;
	}
	
	# FIFO
	if (S_ISFIFO($st->mode()))
	{
		blag "Creating fifo: " . strim($item);
		mkfifo("$BACKUP_DEST/$BASE_NAME/$item", $st->mode()) or blag "Unable to create fifo: $!";
		chown $st->uid(), $st->gid(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change ownership: $!";
		$STATS{'created_fifos'}++;
		return;
	}
	
	# Block, Char & Socket
	if (S_ISBLK($st->mode()) || S_ISCHR($st->mode()) || S_ISSOCK($st->mode()))
	{
		blag "Creating node: " . strim($item);
		mknod("$BACKUP_DEST/$BASE_NAME/$item", $st->mode(), $st->rdev()) and blag "Unable to create node: $!";
		chown $st->uid(), $st->gid(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change ownership: $!";
		$STATS{'created_nodes'}++;
		return;
	}
	
	if (S_ISREG($st->mode()))
	{
		if (($st2 = lstat("$BACKUP_DEST/$PREV_BASE_NAME/$item")))
		{
			# Check if anything has changed since previous backup.
			if (
				$st->mode() == $st2->mode() &&
				$st->uid() == $st2->uid() &&
				$st->gid() == $st2->gid() &&
				$st->size() == $st2->size() &&
				$st->mtime() == $st2->mtime()
			)
			{
				blag "Hard linking file: " . strim($item);
				link "$BACKUP_DEST/$PREV_BASE_NAME/$item", "$BACKUP_DEST/$BASE_NAME/$item" or blag "Create hard link: $!";
				$STATS{'created_hardlinks'}++;
				return;
			}
		}
		
		# No previous backup, or something has changed.
		blag "Backing up file: " . strim($item);
		copy($item, "$BACKUP_DEST/$BASE_NAME/$item") or do
		{
			blag "Unable to copy file: $!";
			return;
		};

		chown $st->uid(), $st->gid(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change ownership: $!";
		chmod $st->mode(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to change mode: $!";
		utime $st->atime(), $st->mtime(), "$BACKUP_DEST/$BASE_NAME/$item" or blag "Unable to update access and modification times: $!";
		$STATS{'copied_files'}++;
		$STATS{'copied_bytes'} += $st->size();
		
		return;
	}

	blag "Unknown item, skipping: " . strim($item);
	$STATS{'unknown_items'}++;
}

# Logs stuff to the log file
sub blag
{
	$t = localtime;
	foreach (@_)
	{
		$str = sprintf("[%04d-%02d-%02d %02d:%02d:%02d] %s\n", $t->year(), $t->mon(), $t->mday, $t->hour(), $t->min(), $t->sec(), $_);
		print LOGFILE $str;
		print $str if $VERBOSE;
	}
}

# Locates and returns the previous backup run. If none is found, a dummy directory is created and returned.
sub find_previous_backup
{
	my @dirs = ();

	opendir DIR, $BACKUP_DEST or die "Unable to open backup destination directory\n";
	while (my $d = readdir DIR)
	{
		push @dirs, $d if -d "$BACKUP_DEST/$d" && $d =~ /^backup_/o;
	}
	closedir DIR;

	unless (scalar @dirs)
	{
		my $zeropath = "$BACKUP_DEST/$ZERO_BACKUP_DIR";
		
		eval { mkpath $zeropath unless -d $zeropath };
		die "Unable to create dummy first backup directory: $zeropath\n" if $@;
		push @dirs, $ZERO_BACKUP_DIR;
	}
	
	@rev = reverse sort @dirs;
	shift @rev;
}

# Trim supurfluous slashes
sub strim
{
	my $str = shift;
	$str =~ s/\/{2,}/\//o;
	$str;
}
