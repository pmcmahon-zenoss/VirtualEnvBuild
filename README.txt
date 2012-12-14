== Prerequisites ==

Oracle Java JDK 1.6 update 37.

# emerge sun-jdk

(This will require a license to be accepted and the JDK bin to be manually
downloaded)

Maven 3.

# emerge maven-bin

Subversion:

# emerge subversion

Sudo:

# emerge sudo

== Zenoss user ==

A zenoss user and group must exist and currently requires passwordless sudo
root access. Set up a /home/zenoss home directory and bash as a default shell.
Often, it is easiest to add the zenoss user to the wheel group and then
uncomment the line in /etc/sudoers (via "visudo") that gives wheel
passwordless root access. The sudo access is only required for the build, not
for zenoss itself to run.

Note: It appears that mkzopeinstance doesn't like being run as root,
and this may be the only real issue with doing a pure build as root.

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

== MANUAL TODOS AFTER INSTALL?==

* install etc/* files if they dont exist.
* manually fix path for /opt/zenoss/bin/zendmd (and potentially others) to
  reference $ZENHOME/venv/bin/python

== DEVELOPMENT TODO ==

* get build working as root
* get build installing stuff to places other than /opt/zenoss
* support target directories other than /opt/zenoss
