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

    $0 trunk
    $0 branch [BRANCH_VERSION]
    $0 tag [TAG_VERSION]

Examples:

$ $0 trunk

This will create a an archive named zenoss-trunk-20130101.tar.xz containing a
trunk svn checkout.

$ $0 branch 4.2.x

This will create an archive named zenoss-branch-4.2.x-20130101.tar.xz
containing a branch svn checkout, in this case from the stable 4.2.x branch.

$ $0 tag 4.2.3

This will create an archive named zenoss-release-4.2.3.tar.xz containing
a tag 4.2.3 svn checkout -- the 4.2.3 release archive. The timestamp is
not included in the archive name because the tag should not change.

EOF
}
timestamp=$(date +%Y%m%d)

if [ "$1" = "trunk" ]; then
	# trunk build
	branch="trunk/core"
	archive_name="zenoss-trunk-$timestamp"
	# archive will be named zenoss-trunk-20130101.tar.xz
elif [ "$1" = "branch" ]; then
	if [ "$2" = "" ]; then
		die "Please specify a branch version as second argument, such as 4.2.x."
	fi
	# stable branch build, first arg is "stable", second is "4.2.x"
	branch="branches/core/zenoss-$2"
	archive_name="zenoss-branch-$2-$timestamp"
	# archive will be named zenoss-stable-4.2.x-20130101.tar.xz
elif [ "$1" = "tag" ]; then
	if [ "$2" = "" ]; then
		die "Please specify a tag version as a second argument, such as 4.2.3."
	fi
	# tag build - aka "4.2.3"
	branch="tags/core/zenoss-$2"
	archive_name="zenoss-release-$2"
	# archive will be named zenoss-release-4.2.3.tar.xz
else
	help && exit 1
fi

svn co http://dev.zenoss.com/svnint/$branch $archive_name || die "svn fail"
tar cJvf $archive_name.tar.xz $archive_name || die "tar fail"
