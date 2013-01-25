#!/bin/bash

die() {
	echo $*
	exit 1
}

help() {
cat << EOF
$0: 
    use svn to create a source tarball of a Zenoss release, branch or tag.

Usage:

Create tarballs from public svn:

    $0 trunk
    $0 branch [BRANCH_VERSION]
    $0 tag [TAG_VERSION]

Create tarballs from internal (Zenoss, Inc.) svn:

    $0 internal trunk
    $0 internal branch [BRANCH_VERSION]
    $0 internal tag [TAG_VERSION]

Examples:

$ $0 trunk

This will create a an archive named zenoss-dev-20130101.tar.xz containing a
trunk svn export.

$ $0 branch 4.2.x

This will create an archive named zenoss-branch-4.2.x-20130101.tar.xz
containing a branch svn export, in this case from the stable 4.2.x branch.

$ $0 tag 4.2.3

This will create an archive named zenoss-release-4.2.3.tar.xz containing
a tag 4.2.3 svn export -- the 4.2.3 release archive. The timestamp is
not included in the archive name because the tag should not change.

EOF
}

if [ "$1" = "internal" ]; then
	url="http://dev.zenoss.com/svnint"	
	internal="yes"
	shift
else
	url="http://dev.zenoss.org/svn/"
	internal="no"
fi

timestamp=$(date +%Y%m%d)

if [ "$1" = "trunk" ]; then
	# trunk build
	[ "$internal" = "yes" ] && branch="trunk/core" || branch="trunk"
	archive_name="zenoss-dev-$timestamp"
	# archive will be named zenoss-trunk-20130101.tar.xz
elif [ "$1" = "branch" ]; then
	if [ "$2" = "" ]; then
		die "Please specify a branch version as second argument, such as 4.2.x."
	fi
	# stable branch build, first arg is "stable", second is "4.2.x"
	[ "$internal" = "yes" ] && branch="branches/core/zenoss-$2" || branch="branches/zenoss-$2"
	archive_name="zenoss-stable-$2-$timestamp"
	# archive will be named zenoss-stable-4.2.x-20130101.tar.xz
elif [ "$1" = "tag" ]; then
	if [ "$2" = "" ]; then
		die "Please specify a tag version as a second argument, such as 4.2.3."
	fi
	# tag build - aka "4.2.3"
	[ "$internal" = "yes" ] && branch="tags/core/zenoss-$2" || branch="tags/zenoss-$2"
	archive_name="zenoss-release-$2"
	# archive will be named zenoss-release-4.2.3.tar.xz
else
	help && exit 1
fi
if [ -e "$archive_name.tar.xz" ]; then
	die "Archive $archive_name.tar.xz already exists. Not creating new archive."
fi
CURDIR=$(pwd)
TMPDIR=/var/tmp/$0.$$
install -d $TMPDIR || die "tmpdir create"
svn export $url/$branch $TMPDIR/$archive_name || die "svn fail"
echo "Creating $CURDIR/$archive_name.tar.xz..."
tar cJvf $CURDIR/$archive_name.tar.xz -C $TMPDIR $archive_name || die "tar fail"
echo 'Cleaning up temp dir...'
rm -rf $TMPDIR 
echo "Done!"
