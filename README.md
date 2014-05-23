alwork-bash
===========

Alwork-bash is a bash script that helps users to focus on their daily work by blocking specified web addresses a limited amount of time.

Supports public humiliation by sending an email to a friend if the blocking is cancelled before the specified amount of time.

# Usage
Simply install the requirements listed below and run the shell script. The following will happen:
* A configuration file `~/.alworkbashrc` is automatically created on the first run, and the user is asked if it wants to edit it. If so, the configuration file is opened in an editor. If not, only YouTube will be blocked when running.
* Alwork-bash forces itself to run as root by using gksudo, so the user is asked for its password.
* The following is repeated in a loop:
  * A popup is opened in which the user can specify the amount of time (hours in decimal format) to block the URLs.
  * A 'work' progress bar and a 'Cancel' button is shown.
  * If cancelled before the time is up and the public humiliation has been configured, the user is asked for the reason to cancel the blocking before the specified amount of time.



# Configuration
```bash
# Configuration of your own email address.
# WARNING: Use a junk address and password, since this file is saved in clear text
AW_FROM_NAME="Alwork Notifyer" # Your name
AW_FROM_EMAIL="" # Your email address
AW_FROM_EMAIL_PW="" # Your email password
AW_FROM_SERVER_TLS="yes"
AW_FROM_SERVER="smtp.gmail.com" # Your email server

# Your friends email address/es (comma or semicolon separated list)
AW_TO_EMAIL=""

# URLs to block
BLACKLIST=(
youtube.com
www.youtube.com
)
```

# Requirements
* iptables
* zenity
* sudo
* gksu (command gksudo)
* xdg-utils (command xdg-open)
* libnotify-bin (command notify-send)
* sendemail (optional)
