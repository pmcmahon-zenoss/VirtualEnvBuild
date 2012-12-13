#!/usr/bin/env bash
##############################################################################
# 
# Copyright (C) Zenoss, Inc. 2012, all rights reserved.
# 
# This content is made available according to terms specified in
# License.zenoss under the directory where your Zenoss product is installed.
# 
##############################################################################

###########################################################################
#
# TODO: Make DESTDIR friendly.
#
###########################################################################
BN=${0##*/}

#-------------------------------------------------------------------------#
# Autoconf substitution variables populated during the configure step.
#
#                            +-------------+
# mkzenossinstance.sh.in --> | ./configure | --> mkzenossinstance.sh
#                            +-------------+
#
# NOTE:
# Please make bug fixes to mkzenossinstance.sh.in and then re-run 
# configure to generate the uplevel mkzenossinstance.sh script.
#-------------------------------------------------------------------------#
#
INSTDIR=/home/zenoss/VirtualEnvBuild/inst
RABBITMQ_HOST=localhost
RABBITMQ_PASS=zenoss
RABBITMQ_PORT=5672
RABBITMQ_REQ_VERSION=2.8.6
RABBITMQ_SSL=0
RABBITMQ_USER=zenoss
RABBITMQ_VHOST=/zenoss
prefix=/opt/zenoss
ZENHOME=/opt/zenoss
ZENGROUP=zenoss
ZOPEHOME=${prefix}/zopehome
ZOPEPASSWORD=zenoss
ZOPE_LISTEN_PORT=8080
ZOPE_USERNAME=admin     # btw, who uses this on a src build?
ZODB_SOCKET=
#-------------------------------------------------------------------------#
SUCCESS=0
E_RABBITMQ=100
E_MISSING_STARTUP=101
E_MKZOPE=102
# No longer used.
# E_NO_AMQP_UTIL_JAR=103
E_BAD_ENV_SETUP=104
E_MISSING_ZOPE_CONF=105
E_BAD_ZOPE_CONF_SYNC=106
E_BAD_ZODB_CREATE=107
E_BAD_ZODB_MAIN_CREATE=108
E_BAD_ZEP_SESSION_CREATE=109
E_MISSING_ZENBUILD=110
E_BAD_ZENBUILD=111
E_MISSING_ZENMIGRATE=112
E_BAD_ZENMIGRATE=113
E_BAD_RABBITMQ_SERVER_VERSION_CHECK=114
E_BAD_GLOBALCONF_GET=115
E_MISSING_GLOBAL_CONF=116
E_NO_EXEC_PERM=117

# Sets various envvars we'll need from global.conf.
STARTUP_ENV_SH=startup_env.sh

# Zenoss-specific zope.conf.
ZENOSS_CONF=${ZENHOME}/etc/zenoss.conf

# Overwritten by zenoss.conf.
ZOPE_CONF=${ZENHOME}/etc/zope.conf

ZODB_SCHEMA_DIR=${ZENHOME}/Products/ZenUtils/relstorage

# Primitive for building zentinel portal and device management database.
ZENBUILD=${ZENHOME}/bin/zenbuild

# Primitive for managing object model changes to the dmd not yet reflected in 
# xml files we export from the dmd and check-in periodically especially on 
# release boundaries.
ZENMIGRATE=${ZENHOME}/bin/zenmigrate

# TODO: Autoconfize this.  
# One day we'll support python not under ZENHOME :-)
PYTHON=${ZENHOME}/venv/bin/python

# TODO: Autoconfize this.  
# Place to look for python modules when importing stuff.
PYTHONPATH=${ZENHOME}/lib/python

# Primitive for parsing / managing global.conf.
ZENGLOBALCONF=${ZENHOME}/bin/zenglobalconf

# Contains ZEP, ZODB, and RabbitMQ settings.
GLOBALCONF=${ZENHOME}/etc/global.conf

# Stuff we want to tease out of global.conf and export
# as environment variables.  Apparently some zenoss 
# primitives rely upon environment variables for some
# attributes.  Would be nice to kill this one day.
#
if [ -n "${ZODB_SOCKET}" ];then
	#
	# We hit this path when configured for ZenDS-based ZODB.
	#
	# We really only need ZODB_SOCKET in ZenDS scenario where we're 
	# bypassing the default location of the socket baked into the mysql 
	# client  (e.g., /var/lib/mysql/mysql.sock).
	#
	# The ./configure script is written to generate null ZODB_SOCKET 
	# values otherwise.
	#
	ZODB_SOCKET_zodb_socket=ZODB_SOCKET:zodb-socket
fi
ENVVARS_GCVARS="\
	ZODB_DB_TYPE:zodb-db-type 		\
	ZODB_HOST:zodb-host 			\
	ZODB_DB:zodb-db				\
	ZODB_PORT:zodb-port 			\
	ZODB_ADMIN_USER:zodb-admin-user		\
	ZODB_ADMIN_PASSWORD:zodb-admin-password	\
	ZODB_USER:zodb-user 			\
	ZODB_PASSWORD:zodb-password 		\
	ZEP_DB_TYPE:zep-db-type 		\
	ZEP_HOST:zep-host 			\
	ZEP_DB:zep-db				\
	ZEP_PORT:zep-port			\
	ZEP_ADMIN_USER:zep-admin-user 		\
	ZEP_ADMIN_PASSWORD:zep-admin-password 	\
	ZEP_USER:zep-user 			\
	ZEP_PASSWORD:zep-password		\
	RABBITMQ_HOST:amqphost			\
	RABBITMQ_SSL:amqpusessl			\
	RABBITMQ_PORT:amqpport			\
	RABBITMQ_VHOS:amqpvhost			\
	RABBITMQ_USER:amqpuser			\
	RABBITMQ_PASS:amqppassword		\
	${ZODB_SOCKET_zodb_socket}		\
"

#-------------------------------------------------------------------------#
# Functions
#-------------------------------------------------------------------------#

#-------------------------------------------------------------------------#
function get_globalconf_val 
{
	# e.g., given zodb-db-type, return "mysql"

	var_name=$1
	zenglobalconf=$2
	rc=${SUCCESS}

	val=`${zenglobalconf} -p ${var_name}`
	if [ $? -eq ${SUCCESS} ]; then
		echo ${val}
	else
		rc=${E_BAD_GLOBALCONF_GET}
	fi
	return ${rc}
}  # end get_globalconf_val()

#-------------------------------------------------------------------------#
function export_globalconf()
{
	# Parse global.conf and export the results to individual 
	# environment variables for subsequent consumption by zenoss primitives.

	zenglobalconf=$1
	globalconf=$2
	envvars_gcvars="$3"

	rc=${SUCCESS}
	#
	# Use the following to flag when at least one error was encountered
	# while parsing globalconf.
	#
	rc_latch=${SUCCESS}

	#
	# Pre-req checking.  Does global.conf exist?
	#
	echo -n "Checking ${globalconf}: "
	if [ -f "${globalconf}" ];then
		echo "[ OK ]"
	else
		if [ -f "${globalconf}.example" ];then
			if cp ${globalconf}.example ${globalconf} ;then
				echo "[ OK ] Bootstrapped from global.conf.example."
			else
				echo "[FAIL] Missing."
				rc=${E_MISSING_GLOBAL_CONF}
			fi
		else
			echo "[FAIL] Missing."
			rc=${E_MISSING_GLOBAL_CONF}
		fi
	fi

	#
	# Does the zenglobalconf primitive exist?
	#
	if [ ${rc} -eq ${SUCCESS} ];then
		echo -n "Checking ${zenglobalconf}: "
		if [ -f "${zenglobalconf}" -a -x "${zenglobalconf}" ];then
			echo "[ OK ]"
		else
			if [ ! -x "${zenglobalconf}" ];then
				echo "[FAIL] No execute permission."
				rc=${E_NO_EXEC_PERM}
			else
				echo "[FAIL] Missing."
				rc=${E_MISSING_GLOBAL_CONF}
			fi
		fi
	fi

	#
	# Now loop through all the global.conf parameters we need and 
	# export as environment variables.  
	#
	# Editorial: This is slightly lame in that the zenoss primitives 
	#            should support command line options rather than feeding 
	#            off of these envvars.
	#
	rc_latch=${rc}
	if [ ${rc} -eq ${SUCCESS} ];then
		for envvar_gcvar in ${envvars_gcvars}
		do
			envvar=`echo ${envvar_gcvar}|cut -d: -f1`
			gcvar=`echo ${envvar_gcvar} |cut -d: -f2`
			gcval=$(get_globalconf_val ${gcvar} ${zenglobalconf})
			rc=$?
			if [ ${rc} -eq ${SUCCESS} ] ;then
				eval "export ${envvar}=${gcval}"
				echo "export ${envvar}=${gcval}"
			else
				if [ ${gcvar} != "zodb-socket" ] ; then
					if [ ${rc_latch} -eq ${SUCCESS} ];then
						rc_latch=${rc}
					fi
					echo "Error: Unable to read ${gcvar} from ${GLOBALCONF}."
				else
					echo "Info: Unable to read ${gcvar} from ${GLOBALCONF}; skipping..."
				fi
			fi
		done
	fi
	return ${rc_latch}
} # end export_globalconf()

#-------------------------------------------------------------------------#
validate_rabbitmq()
{
	local required_version=${RABBITMQ_REQ_VERSION}
	local sslarg=""
	local rc=${SUCCESS}

	if [ "${RABBITMQ_SSL}" = "1" ]; then
		sslarg="-s"
	fi
    
	echo -n "Checking RabbitMQ required version (${required_version}): "
	${PYTHON} ${ZENHOME}/Products/ZenUtils/qverify.py ${required_version} > /dev/null
	rc=$?	
	if [ ${rc} -eq 0 ]; then
		echo "[ OK ]"
	else
		echo "[FAIL]"
		cat - <<-EOF

Is RabbitMQ Server (version = ${required_version}) running?

For example, on Red Hat / CentOS distros:

    sudo service rabbitmq-server start
    sudo service rabbitmq-server status
        
Have you configured RabbitMQ for Zenoss?

    sudo rabbitmqctl add_user ${RABBITMQ_USER} ${RABBITMQ_PASS}
    sudo rabbitmqctl add_vhost ${RABBITMQ_VHOST}
    sudo rabbitmqctl set_permissions -p ${RABBITMQ_VHOST} ${RABBITMQ_USER} '.*' '.*' '.*'

EOF
		rc=${E_BAD_RABBITMQ_SERVER_VERSION_CHECK}
	fi
	return ${rc}
} # end validate_rabbitmq()

#-------------------------------------------------------------------------#
# replace SEARCH with REPLACE in $FILE using sed
replace() 
{
	SEARCH=$1
	REPLACE=$2
	FILE=$3
	TEMP=/tmp/`basename $FILE`

	sed -e "s%${SEARCH}%${REPLACE}%g" < ${FILE} > ${TEMP}
	mv ${TEMP} ${FILE}
} # end replace()

#-------------------------------------------------------------------------#
setuidRoot() 
{
	theGroup=$1
	theDir=$2
	theFiles=$3

	theOwner=root
	thePerms=04750

	# sudo version <= 1.6 does not support -n option
	if sudo -n ls 1>/dev/null 2>&1 ; then
		no_pw_prompt_opt="-n"
	fi

	echo -n "Changing ownership [${theOwner}:${theGroup}] of ${theDir}/{${theFiles}}: "
	if chown ${theOwner}:${theGroup} ${theDir}/{${theFiles}} 2>/dev/null ;then
		echo "[ OK ]"
		echo -n "Changing permissions [${thePerms}] on ${theDir}/{${theFiles}}: "
		if chmod ${thePerms} ${theDir}/{${theFiles}} 2>/dev/null ;then
			echo "[ OK ]"
		else
			if [ -n "${no_pw_prompt_opt}" ]; then
				sudo ${no_pw_prompt_opt} chmod ${thePerms} ${theDir}/{${theFiles}} 2>/dev/null
				if [ $? -eq 0 ]; then
					echo "[ OK ]"
				else
					echo "[FAIL]"
					echo
					echo "Make sure to execute:"
					echo
					echo "    sudo chmod ${thePerms} ${theDir}/{${theFiles}}"
				fi
			else
				echo "[FAIL]"
				echo
				echo "Make sure to execute:"
				echo
				echo "    sudo chmod ${thePerms} ${theDir}/{${theFiles}}"
			fi
		fi
	else
		if [ -n "${no_pw_prompt_opt}" ]; then
			sudo ${no_pw_prompt_opt} chown ${theOwner}:${theGroup} ${theDir}/{${theFiles}} 2>/dev/null
			if [ $? -eq 0 ]; then
				echo "[ OK ]"
			else
				echo "[FAIL]"
				echo
				echo "Make sure to execute:"
				echo
				echo "    sudo chown ${theOwner}:${theGroup} ${theDir}/{${theFiles}}"
				echo "    sudo chmod ${thePerms} ${theDir}/{${theFiles}}"
			fi
		else
			echo "[FAIL]"
			echo
			echo "Make sure to execute:"
			echo
			echo "    sudo chown ${theOwner}:${theGroup} ${theDir}/{${theFiles}}"
			echo "    sudo chmod ${thePerms} ${theDir}/{${theFiles}}"
		fi
	fi
} # end chownStuff()

#-------------------------------------------------------------------------#
# main
#-------------------------------------------------------------------------#
rc=${SUCCESS}

export PYTHON
export PYTHONPATH
export ZENHOME
export ZOPEHOME
export ZOPEPASSWORD
export ZOPE_LISTEN_PORT
export ZOPE_USERNAME

export_globalconf ${ZENGLOBALCONF} ${GLOBALCONF} "${ENVVARS_GCVARS}"
rc=$?

if [ ${rc} -eq ${SUCCESS} ];then
	validate_rabbitmq
	rc=$?
fi

#-------------------------------------------------------------------------#
# Make Zope instance.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo -n "Creating Zope instance: "
	${PYTHON} ${ZOPEHOME}/mkzopeinstance --dir="${ZENHOME}" --user="admin:${ZOPEPASSWORD}"
	rc=$?
	if [ ${rc} -eq ${SUCCESS} ];then
		echo "[ OK ]"
		# Wait for processes to start up.
		sleep 2
	else
		echo "[FAIL]"
	fi
fi

#-------------------------------------------------------------------------#
# Re-establish good zope.conf from zenoss.conf since the call to
# mkzopeinstance above is destructive in that way.
#
# TODO: Remove inst/conf/zope.conf since it gets replaced by zenoss.conf
#       anyway.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo -n "Checking for ${ZOPE_CONF}: "
	if [ -f "${ZOPE_CONF}" ]; then
		if [ -f "${ZENOSS_CONF}" ] ; then
			mv ${ZENOSS_CONF} ${ZOPE_CONF}
			echo "[ OK ] Replaced by ${ZENOSS_CONF}."
		else
			echo "[ OK ]"
		fi
		# TODO: Autoconf-ize zenoss.conf so we can kill this.
		replace "<<INSTANCE_HOME>>" "$ZENHOME" ${ZOPE_CONF}
		replace "effective-user zenoss" "effective-user $USERNAME" ${ZOPE_CONF}
	else
		echo "[FAIL]"
		rc=${E_MISSING_ZOPE_CONF}
	fi
fi

#-------------------------------------------------------------------------#
# Sync out settings from:
#
#     global.conf  ----> zodb_db_main.conf
#                   |
#                   +--> zodb_db_session.conf
#
# especially with regard to Zope relstorage connection credentials.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo -n "Ensuring the Zope relstorage connection has credentials: "
	if zenglobalconf --sync-zope-conf  ;then
		echo "[ OK ]"
	else
		echo "[FAIL]"
		rc=${E_BAD_ZOPE_CONF_SYNC}
	fi
fi

#-------------------------------------------------------------------------#
# Create main ZODB relstorage database.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo "Dropping and recreating main ZODB relstorage database: ..."
	if zeneventserver-create-db --dbtype ${ZODB_DB_TYPE} --dbhost ${ZODB_HOST} --dbport ${ZODB_PORT} --dbadminuser ${ZODB_ADMIN_USER} --dbadminpass "${ZODB_ADMIN_PASSWORD}" --dbuser ${ZODB_USER} --dbpass "${ZODB_PASSWORD}" --dbname ${ZODB_DB} --schemadir ${ZODB_SCHEMA_DIR} ; then
		echo "[ OK ]"
	else
		echo "[FAIL]"
		rc=${E_BAD_ZODB_MAIN_CREATE}
	fi
fi

#-------------------------------------------------------------------------#
# Create session ZODB relstorage database.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo "Dropping and recreating session ZODB relstorage database: ..."
	if zeneventserver-create-db --dbtype ${ZODB_DB_TYPE} --dbhost ${ZODB_HOST} --dbport ${ZODB_PORT} --dbadminuser ${ZODB_ADMIN_USER} --dbadminpass "${ZODB_ADMIN_PASSWORD}" --dbuser ${ZODB_USER} --dbpass "${ZODB_PASSWORD}" --dbname ${ZODB_DB}_session --schemadir ${ZODB_SCHEMA_DIR} ; then
		echo "[ OK ]"
	else
		echo "[FAIL]"
		rc=${E_BAD_ZODB_SESSION_CREATE}
	fi
fi

#-------------------------------------------------------------------------#
# Create zenoss-zep database.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo "Dropping and recreating zenoss-zep database: ..."
	if zeneventserver-create-db --dbtype ${ZEP_DB_TYPE} --dbhost ${ZEP_HOST} --dbport ${ZEP_PORT} --dbadminuser ${ZEP_ADMIN_USER} --dbadminpass "${ZEP_ADMIN_PASSWORD}" --dbuser ${ZEP_USER} --dbpass "${ZEP_PASSWORD}" --dbname "${ZEP_DB}"; then
		echo "[ OK ]"
	else
		echo "[FAIL]"
		rc=${E_BAD_ZEP_CREATE}
	fi
fi

#-------------------------------------------------------------------------#
# Build the zentinel portal object and Device Management Database (dmd).
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo "Running zenbuild: ..."
	if [ -f "${ZENBUILD}" ] ;then
		if [ -x "${ZENBUILD}" ];then
			if ${ZENBUILD} ;then
				echo "[ OK ]"
			else
				echo "[FAIL]"
				rc=${E_BAD_ZENBUILD}
			fi
		else
			echo "[FAIL] Unable to execute."
			rc=${E_BAD_ZENBUILD}
		fi
	else
		echo "[FAIL] Missing."
		rc=${E_MISSING_ZENBUILD}
	fi
fi

#-------------------------------------------------------------------------#
# Perform any data migration implied by changes to the object model
# using migrate steps in the base product and zenpacks.
#
# This handles the case where changes to the object model have
# not yet rippled through to the xml that gets dumped and checked-in
# and processed above when bootstrapping the dmd.
#
# NB: Should probably flag/nag any object model changes coming out of 
#     this step as a reminder to devs to dump and check-in updated 
#     DMD object xml?
#
# TODO: Add build target to do this on demand.
#-------------------------------------------------------------------------#
if [ ${rc} -eq ${SUCCESS} ];then
	echo "Running zenmigrate: ..."
	if [ -f "${ZENMIGRATE}" ] ;then
		if [ -x "${ZENMIGRATE}" ];then
			if ${ZENMIGRATE} ;then
				echo "[ OK ]"
			else
				echo "[FAIL]"
				rc=${E_BAD_ZENMIGRATE}
			fi
		else
			echo "[FAIL] Unable to execute."
			rc=${E_BAD_ZENMIGRATE}
		fi
	else
		echo "[FAIL] Missing."
		rc=${E_MISSING_ZENMIGRATE}
	fi
fi

if [ ${rc} -eq ${SUCCESS} ];then
	setuidRoot ${ZENGROUP} ${ZENHOME}/bin "pyraw,zensocket,nmap"
	cat - <<-EOF

		To manage the operational state of Zenoss, run:

		    zenoss [start|stop|status]

EOF
	echo "-------------------------------------------------------------------------"
	echo "[DONE]"
else
	cat - <<-EOF
		${BN}: rc=${rc}
		Please investigate.

EOF
fi
