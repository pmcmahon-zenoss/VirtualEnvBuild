== Prerequisites ==

Oracle Java 1.6 update 31 or greater.
maven-bin installed.
subversion installed.

== Zenoss user ==

A zenoss user and group must exist and currently requires passwordless sudo root access.
It appears that mkzopeinstance doesn't like being run as root, and this may be
the only real issue with doing a pure build as root.

=== build_deps will install: ===

The following packages will be instaleld by build_deps.sh:

RDEPEND="mysql rrdtool openldap rabbitmq-server net-snmp"
DEPEND="zip unzip subversion"

=== Starting the build process ===

First, check out this source tree and place it in
/home/zenoss/VirtualEnvBuild. Ensure that all the prerequisites above are met.
Then, enter VirtualEnvBuild and run the following scripts:

$ ./build_zenoss.sh
$ source /opt/zenoss/venv/bin activate
$ ./mkzenossinstance.sh

== TODO ==

* install etc/* files if they dont exist.
* manually fix path for /opt/zenoss/bin/zendmd (and potentially others) to
  reference $ZENHOME/venv/bin/python

