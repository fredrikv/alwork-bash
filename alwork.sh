#!/bin/bash
CONF_FILE=~/.alworkbashrc
function lastConfEdit { echo $(date -r "$CONF_FILE" +%s); }
LAST_CONF_EDIT=0
RELOAD_INTERVAL=5
UUID=$(uuidgen)
NOTIFY_LOOP_PID=0


# Create a default config file in the home directory
function createDefaultConfig {
	sudo -u $(whoami) touch "$CONF_FILE"
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
)' >> "$CONF_FILE"

	if [ $? -eq 0 ]; then
		zenity --question --title="New configuration file" --text="New configuration file created. Do you want to update it?"
		if [ $? -eq 0 ]; then
			xdg-open "$CONF_FILE"
		fi
	else
		zenity --warning --title="Error" --text="Configuration file could not be created. Closing..."
		exit
	fi
}

# Load config file if changed.
function loadConfig {
	if [[ ( $LAST_CONF_EDIT -lt $(lastConfEdit) && $RELOAD_INTERVAL -ge 0 ) || ( $LAST_CONF_EDIT -eq 0 && $RELOAD_INTERVAL -lt 0 ) ]]; then
		LAST_CONF_EDIT=$(lastConfEdit)
		source "$CONF_FILE"
		if [ $? -ne 0 ]; then
			createDefaultConfig
			source "$CONF_FILE"
			return $?
		fi
		return 0
	fi
	return 1
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
	START=$(date +%s)
	TOTAL=$(echo "3600*$1"|bc)
	TOTAL=${TOTAL%.*}
	FINISH=$(($START+$TOTAL))
	NEXT_RELOAD=$START
	blacklistAll
	while [ $(date +%s) -lt $FINISH ]; do
		CURRENT_TIME=$(date +%s)
		ELAPSED=$(($CURRENT_TIME-$START))

		PERCENTAGE=$(echo "scale=4; 100*($ELAPSED)/${TOTAL}"|bc)
		echo $PERCENTAGE

		# Reload config and blacklist every minute
		if [ $RELOAD_INTERVAL -ge 0 ] && [ $CURRENT_TIME -ge $(($NEXT_RELOAD)) ]; then
			loadConfig
			if [ $? -eq 0 ]; then
				removeBlacklisting
				blacklistAll
			fi
			NEXT_RELOAD=$(($CURRENT_TIME+$RELOAD_INTERVAL))
		fi

		sleep 1
	done
	removeBlacklisting
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
function startRemindLoop {
	if [ $NOTIFY_LOOP_PID -eq 0 ]; then
		osdNotifyLoop "Alwork not started" "Alwork is currently not started. Remember to [re]activate it." 300 &
		NOTIFY_LOOP_PID=$!
	fi
}

# Stop remind loop
function stopRemindLoop {
	if [ $NOTIFY_LOOP_PID -ne 0 ]; then
		kill $NOTIFY_LOOP_PID
		NOTIFY_LOOP_PID=0
	fi
}


# Send an email with the given title and message.
function sendEmailNotification {
	if [[ "$(command -v sendemail)" != "" && "${AW_FROM_EMAIL}" != "" && "${AW_FROM_EMAIL_PW}" != "" && "${AW_FROM_SERVER}" != "" && "${AW_TO_EMAIL}" != "" ]]; then
		sendemail -f "$AW_FROM_NAME <${AW_FROM_EMAIL}>" -t "$AW_TO_EMAIL" -u "$1" -m "$2" -s $AW_FROM_SERVER -o tls="$AW_FROM_SERVER_TLS" -xu "$AW_FROM_EMAIL" -xp "$AW_FROM_EMAIL_PW" | zenity --progress --title="Sending notification" --text="Sending email notification to ${AW_TO_EMAIL}. Please wait." --pulsate --no-cancel --auto-close
		return $?
	else
		return 1
	fi
}


# Force run as root
if [ "$(id -u)" != "0" ]; then
	loadConfig
	gksudo --preserve-env "${0}"
else
	loadConfig
	# Loop functionality until user decides to quit.
	while [ 1 ]; do
		# Remind user to re/start Alwork every 5 minutes
		startRemindLoop

		# Prompt for work duration
		TIME=$(zenity --entry --title="Work duration" --text="For how many hours will you work?")
		ZENITY_EXIT_CODE=$?

		if [ $ZENITY_EXIT_CODE -eq 1 ]; then
			zenity  --question --ok-label="Yes" --cancel-label="No" --text="Do you really want to quit ${TIME}?"
			if [ $? -eq 0 ]; then
				stopRemindLoop
				exit 0
			else
				stopRemindLoop
				continue
			fi
		fi

		stopRemindLoop

		if [ "${TIME}" != "" ]; then
			# Sleep and handle 'cancel' button
			( (blacklistSleepHours ${TIME}) & echo $!) \
			| (
				read PIPED_PID;
				zenity --progress --auto-close --text="Working..." \
				&& removeBlacklisting \
				&& osdNotify "Break" "You may now have a break." \
				&& sleep 2 \
				|| (
					kill ${PIPED_PID}

					removeBlacklisting

					# Possibly send an email notification
					REASON=""
					if [ "$AW_TO_EMAIL" != "" ]; then
						while [ "${REASON}" == "" ]; do
							startRemindLoop
							REASON=$(zenity --entry --title="Work cancelled" --text="For what reason?")
							stopRemindLoop
						done
						sendEmailNotification "Work cancelled" "${REASON}"
					fi
				)
			)
		fi
	done
fi

