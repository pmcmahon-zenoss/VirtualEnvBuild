== About the Build ==

These build scripts build Zenoss on Funtoo Linux. They work by using the
system's python binaries (version 2.7 must be installed) but create their own
private tree of Python modules located in /opt/zenoss/venv. Using this
approach, Zenoss does not need its own python binary, and all of its python
code is isolated from the distribution's python code.

This approach also leverages the following distribution packages from Funtoo
Linux: java (for zeneventzerver as well as maven-bin for building
zeneventserver), mysql, rrdtool, openldap, net-snmp, pip, and virtualenv.

As the build process matures, I will eventually create an ebuild for Zenoss.
For now, the build steps are documented below. The process is fairly automated
except that quite a few prerequisites must be installed manually in order for
the build to work.

Also note that this build is currently being performed using our internal
(Zenoss, Inc.) subversion repository and will require minor tweaks (as well
as testing) to convert the process over to using the publicly-accessible
subversion repo on zenoss.org. This transition will be made as soon as
the build process is reliable and fully documented.

== Prerequisites ==

The following dependencies also need to be installed and will be eventually
integrated into an ebuild so that they can be automatically satisfied:

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

# emerge zip unzip (not sure if this is just for build or also runtime? Guessing just build)

# emerge dev-db/mysql (our mysql-python requires mysql commands to be available)
# emerge --config mysql (not sure if this is needed for build, or setup?)

# had to run mysql> SET GLOBAL binlog_format = 'MIXED'; at the mysql command
# workaround for what issue? Ask Eric.

add "python" to USE, then:
# emerge rrdtool (rrdtool[python] is needed for the build to complete)

add "sasl" to USE, then:
# emerge openldap

# emerge net-snmp

# emerge dev-python/pip virtualenv

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
