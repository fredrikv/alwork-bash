#!/bin/bash
CONF_FILE=~/.alworkbashrc
UUID=$(uuidgen)


# Create a default config file in the home directory
function createDefaultConfig {
	sudo -u $(whoami) touch $CONF_FILE
	echo '# Configuration of your own email address.
# WARNING: Use a junk address and password, since this file is saved in clear text
AW_FROM_NAME="Alwork Notifyer" # Your name
AW_FROM_EMAIL="" # Your email address
AW_FROM_EMAIL_PW="" # Your email password
AW_FROM_SERVER_TLS="yes"
AW_FROM_SERVER="smtp.gmail.com" # Your email server

# Your friends email address/es (comma or semicolon separated list)
AW_TO_EMAIL=""

# URLs to block
AW_BLACKLIST=(
youtube.com
www.youtube.com
)' >> $CONF_FILE

	if [ $? -eq 0 ]; then
		zenity --question --title="New configuration file" --text="New configuration file created. Do you want to update it?"
		if [ $? -eq 0 ]; then
			xdg-open $CONF_FILE
		fi
	else
		zenity --warning --title="Error" --text="Configuration file could not be created. Closing..."
		exit
	fi
}

# Load config file
function loadConfig {
	source "$CONF_FILE"
	if [ $? -ne 0 ]; then
		createDefaultConfig
		source "$CONF_FILE"
	fi
}

# Blacklist a single website
function blacklist {
	iptables -A OUTPUT -p tcp -m string --string "${1}" --algo kmp -j DROP -m comment --comment "${UUID}"
}

# Remove blacklisting of all websites in config file
function removeBlacklisting {
	iptables-save | grep -v ${UUID} | iptables-restore
}

# Blacklist all websites in the AW_BLACKLIST array
function blacklistAll {
	for SITE in ${AW_BLACKLIST[*]}; do
		blacklist ${SITE}
	done
}

# Sleep n.n hours while counting up to 100
function blacklistSleepHours {
	TOTAL=$(echo "3600*$1"|bc)
	TOTAL=${TOTAL%.*}
	START=$(date +%s)
	FINISH=$(($START+$TOTAL))
	ITERATION=0

	while [ $(date +%s) -lt $FINISH ]; do
		CURRENT_TIME=$(date +%s)
		ELAPSED=$(($CURRENT_TIME-$START))

		PERCENTAGE=$(echo "scale=4; 100*($ELAPSED)/${TOTAL}"|bc)
		echo $PERCENTAGE

		# Reload config and blacklist every minute
		if [ $ELAPSED -ge $(($ITERATION*60)) ]; then
			loadConfig
			blacklistAll
		fi

		let ITERATION++

		sleep 1
	done
	echo 100
}

# Send OSD message to user
function osdNotify {
	sudo -u $(whoami) notify-send "$1" "$2"
}

# Send OSD message to user every n seconds in infinite loop
function osdNotifyLoop {
	while [ true ]; do
		osdNotify "$1" "$2"
		sleep "$3"
	done
}

# Loop for reminding user about activating Alwork
function remindStartLoop {
	osdNotifyLoop "Alwork not started" "Alwork is currently not started. Remember to [re]activate it." 300
}


# Send an email with the given title and message.
function sendEmailNotification {
	loadConfig
	if [[ $(command -v sendemail) -eq 0 && "${AW_FROM_EMAIL}" != "" && "${AW_FROM_EMAIL_PW}" != "" && "${AW_FROM_SERVER}" != "" && "${AW_TO_EMAIL}" != "" ]]; then
		return sendemail -f "$AW_FROM_NAME <${AW_FROM_EMAIL}>" -t "$AW_TO_EMAIL" -u "$1" -m "$2" -s $AW_FROM_SERVER -o tls="$AW_FROM_SERVER_TLS" -xu "$AW_FROM_EMAIL" -xp "$AW_FROM_EMAIL_PW" | zenity --progress --title="Sending notification" --text="Sending email notification to ${AW_TO_EMAIL}. Please wait." --pulsate --no-cancel --auto-close
	else
		return 1
	fi
}


# Force run as root
if [ "$(id -u)" != "0" ]; then
	loadConfig
	gksudo --preserve-env "${0}"
else
	# Loop functionality until user decides to quit.
	while [ 1 ]; do
		# Remind user to re/start Alwork every 5 minutes
		remindStartLoop &
		NOTIFY_LOOP_PID=$!

		# Prompt for work duration
		TIME=$(zenity --entry --title="Work duration" --text="For how many hours will you work?")
		ZENITY_EXIT_CODE=$?

		kill -9 $NOTIFY_LOOP_PID

		if [ $ZENITY_EXIT_CODE -eq 1 ]; then
			zenity  --question --ok-label="Yes" --cancel-label="No" --text="Do you really want to quit ${TIME}?"
			if [ $? -eq 0 ]; then
				exit 0
			else
				continue
			fi
		fi

		if [ "${TIME}" != "" ]; then
			# Sleep and handle 'cancel'
			( (blacklistSleepHours ${TIME}) & echo $!) \
			| (
				read PIPED_PID; zenity --progress --auto-close --text="Working..." \
				&& removeBlacklisting \
				&& osdNotify "Break" "You may now have a break." && sleep 2 \
				|| (
					kill ${PIPED_PID}

					removeBlacklisting

					# Possibly send an email notification
					loadConfig
					REASON=""
					if [ "$AW_TO_EMAIL" != "" ]; then
						while [ "${REASON}" == "" ]; do
							remindStartLoop &
							NOTIFY_LOOP_PID=$!
							REASON=$(zenity --entry --title="Work cancelled" --text="For what reason?")
							kill -9 $NOTIFY_LOOP_PID
						done
						sendEmailNotification "Work cancelled" "${REASON}"
					fi
				)
			)
		fi
	done
fi

