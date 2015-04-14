#!/bin/bash

policy="Self Service QuickAdd Package"
loggertag="system-log-tag" # JAMF IT uses the tag "jamfsw-it-logs"

# Bundle ID for the package is set here
bundleid="com.yourorg.package" # For example: com.jamfsw.inventorypkg

# URL for the JSS
jssURL="https://your.jss.com" # Replace with your org's JSS

# Username as passed by Self Service: used for assigning in inventory
username=$3

log() {
echo "$1"
/usr/bin/logger -t "$loggertag: $policy" "$1"
}

# Path where package items will be written
pkgtmp="/Library/Application Support/JAMF/tmp/pkg"
/bin/mkdir -p "${pkgtmp}/root/usr/sbin"
/bin/mkdir "${pkgtmp}/scripts"

# TRAP statement and cleanup items upon EXIT
cleanup() {
log "Cleanup: ${pkgtmp}"
/bin/rm -r "${pkgtmp}"
}

trap cleanup exit

jamfbinary="${jssURL}/bin/jamf.gz"

# Set the name of the package that will be generated
# This first line is used to separate first.last usernames - may be un-needed in your environment
firstname=$(echo $username | /usr/bin/awk -F'.' '{print$1}')
today=$(/bin/date +'%Y%m%d')
pkgname="jamfinventory-$firstname-$today.pkg"

# The computer invitation is passed by the JSS
invitation=$4

# Get the home directory of the currently logged in user
localuser=$(/bin/ls -l /dev/console | /usr/bin/awk '{print $3}')
localhome=$(/usr/bin/dscl . read /Users/$localuser | /usr/bin/awk '/NFSHomeDirectory:/ {print $2}')

log "Downloading jamf binary"
/usr/bin/curl -s $jamfbinary -o "${pkgtmp}/root/usr/sbin/jamf.gz"
if [ ! -f "${pkgtmp}/root/usr/sbin/jamf.gz" ]; then
    log "jamf binary failed to download"
    exit 1
fi

# Unzip the jamf binary and set permissions
/usr/bin/gzip -d "${pkgtmp}/root/usr/sbin/jamf.gz"
/bin/chmod 755 "${pkgtmp}/root/usr/sbin/jamf"
/usr/sbin/chown root:staff "${pkgtmp}/root/usr/sbin/jamf"

# Create the postinstall script
log "Writing postinstall"
/bin/cat <<EOF > "${pkgtmp}/scripts/postinstall"
#!/bin/bash

/bin/chmod 555 /usr/sbin/jamf
/usr/sbin/jamf createConf -url $jssURL
/usr/sbin/jamf enroll -invitation $invitation -endUsername $username -noPolicy -noManage

enrolled=$?

if [ \$enrolled -ne 0 ]; then
	echo "Enrollment Failed. The invitation may have expired. Contact IT."
fi

/usr/sbin/jamf removeFramework

exit \$enrolled
EOF

/bin/chmod 755 "${pkgtmp}/scripts/postinstall"
/usr/sbin/chown root:admin "${pkgtmp}/scripts/postinstall"

# If there is an existing copy of the package with the same name it is deleted
if [ -e "$localhome/Downloads/$pkgname" ]; then
    log "Deleting existing package"
    /bin/rm "$localhome/Downloads/$pkgname"
fi

log "Building the package"
/usr/bin/pkgbuild --root "${pkgtmp}/root" --scripts "${pkgtmp}/scripts" --identifier "$bundleid" --version 1 --install-location "/" "$localhome/Downloads/$pkgname"

/usr/bin/open -R "$localhome/Desktop/$pkgname"

exit 0