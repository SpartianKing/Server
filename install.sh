#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 2>&1
  exit 1
fi

 interface=""
  host=github.com
  host_ip=$(getent ahosts "$host" | awk '{print $1; exit}')
  interface=`ip route get "$host_ip" | grep -Po '(?<=(dev )).*(?= src| proto)' | cut -f 1 -d " "`
  ip=$(/sbin/ip -f inet addr show $interface | grep -Po 'inet \K[\d.]+' | head -n 1)
  if [[ $ip == "" ]]; then
    # Never reply with a blank string - instead, use localhost if no IP is found
    # This would be the case if no network connection is non-existent
    ip="127.0.0.1"
  fi
#Lets Install Minecraft
dialog --title "End-User License Agreement"  --yesno "In order to proceed, you must read and accept the EULA at https://account.mojang.com/documents/minecraft_eula\n\nDo you accept the EULA?" 8 60

  case $? in
  0)
   eula="accepted"
   eula_stamp=$(date)
   ;;
  1)
   echo
   echo
   echo "EULA not accepted. You are not permitted to install this software."
   echo
   exit 1 ;;
  esac

  memtotal=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}') # Amount of memory in KB
memavail=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}') # Amount of memory in KB
memvariance=$(($memtotal - $memavail)) # Figure out how much memory is being used so we can make dynamic decisions for this board
mem=$(( (($memtotal - $memvariance) / 1024) - 518)) # Amount of memory in MB
memreservation=$((($memavail * 20/100) / 1024)) # Reserve memory for system (Failure to do this will cause "Error occurred during initialization of VM")
gamemem=$(($mem - $memreservation)) # Calculate how much memory we can give to the game server (in MB)
gamememMIN=$((($mem * 80/100) - 1024)) # Figure a MINIMUM amount of memory to allocate
# Seriously, if you have 100 GB RAM, we don't need more than 12 of it
if (( $gamemem > 12000 )); then
    gamemem=12288
    gamememMIN=1500
fi

if (( $gamememMIN < 0 )); then
  dialog --title "Error" \
    --msgbox "
YOU DON'T HAVE ENOUGH AVAILABLE RAM
Your system shows only $((${memavail} / 1024))MB RAM available, but with the applications running you have only $mem MB RAM available for allocation, which doesn't leave enough for overhead. Typically I'd want to be able to allocate at least 2 GB RAM.
Either you have other things running, or your board is simply not good enough to run a Minecraft server." 18 50
   echo
   echo
   echo "Failed. Not enough memory available for Minecraft server."
   echo
   exit 0

 gamemem=2500
 gamememMIN=1500

fi
else if (( $gamememMIN < 1024 )); then
  dialog --title "warning" --yesno "\nWarning; Either you have other things running, or your system just can't run Minecraft.\n\nWould you like to abort?" 14 50
  case $? in
0)
echo
echo
echo "Aborted."
echo
exit 1 ;;
esac
fi
fi

dialog --title "Installer  --yesno "Automatically load the server on boot?" 6 60
  case $? in
  0)
   cron=1
   ;;
  1)
   cron=0
   ;;
  esac

Server User:
$user

RAM to Allocate:
${gamememMIN##*()}MB - ${gamemem##*()}MB

###############################################
# Create the scripts
###############################################

dialog --infobox "Creating scripts..." 3 34 ; sleep 1

   # Non-forge servers
    echo "exec java ${cli_args} -Xms${gamememMIN}M -Xmx${gamemem}M -jar `server.jar` --nogui --pause" >> ${instdir}server

chmod +x ${instdir}server

if [[ $eula == "accepted" ]]; then
  echo "# https://account.mojang.com/documents/minecraft_eula ACCEPTED by user during installation
# $eula_stamp
eula=true" > ${instdir}eula.txt
fi

# Create the safe reboot script
echo '#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" 2>&1
  exit 1
fi
su - $user -c "'${instdir}'stop"
echo
echo "Rebooting."
/sbin/reboot' > ${instdir}reboot
chmod +x ${instdir}reboot

# Create the safe stop script
echo '#!/bin/bash
user=$(whoami);
if [[ $user != "'${user}'" ]]; then
  if su - '$user' -c "/usr/bin/screen -list" | grep -q Server; then
    printf "Stopping Minecraft Server. This will take time."
    su - '$user' -c "screen -S Server -p 0 -X stuff \"stop^M\""
    running=1
  fi
  chmod a+x ${instdir}stop

#####################################################
#
# Tweaking Server Configs
#####################################################

 # Enable Query
      # Change the value if it exists
      /bin/sed -i '/enable-query=/c\enable-query=true' ${instdir}server.properties
      # Add it if it doesn't exist
      if ! grep -q "enable-query=" ${instdir}server.properties; then
        echo "enable-query=true" >> ${instdir}server.properties
      fi

    # Set game difficulty to Normal (default is Easy, but we want at least SOME challenge)
      # Change the value if it exists
      /bin/sed -i '/difficulty=/c\difficulty=normal' ${instdir}server.properties
      # Add it if it doesn't exist
      if ! grep -q "difficulty=" ${instdir}server.properties; then
        echo "difficulty=normal" >> ${instdir}server.properties
      fi

  # Change the value if it exists
      /bin/sed -i '/view-distance=/c\view-distance=7' ${instdir}server.properties
      # Add it if it doesn't exist
      if ! grep -q "view-distance=" ${instdir}server.properties; then
        echo "view-distance=7" >> ${instdir}server.properties
      fi

###############################################
# Install cronjob to auto-start server on boot
###############################################

# Dump current crontab to tmp file, empty if doesn't exist
  crontab -u $user -l > /tmp/cron.tmp 2>/dev/null

  if [[ "$cron" == "1" ]]; then
    # Remove previous entry (in case it's an old version)
    /bin/sed -i~ "\~${instdir}server~d" /tmp/cron.tmp
    # Add server to auto-load at boot if doesn't already exist in crontab
    if ! grep -q "minecraft/server" /tmp/cron.tmp; then
      dialog --infobox "Enabling auto-run..." 3 34 ; sleep 1
      printf "\n@reboot /usr/bin/screen -dmS Server ${instdir}server > /dev/null 2>&1\n" >> /tmp/cron.tmp
      cronupdate=1
    fi
  else
    # Just in case it was previously enabled, disable it
    # as this user requested not to auto-run
    /bin/sed -i~ "\~${instdir}server~d" /tmp/cron.tmp
    cronupdate=1
  fi
   # Import revised crontab
  if [[ "$cronupdate" == "1" ]]
  then
    crontab -u $user /tmp/cron.tmp
  fi

  # Remove temp file
  rm /tmp/cron.tmp

# Start server


  dialog --infobox "Starting the server..." 3 26 ;
  su - $user -c "/usr/bin/screen -dmS Server ${instdir}server"

clear
  echo
  echo
  echo "Installation complete."
  echo
  echo "Minecraft server is now running on $ip"
  echo
  echo "Remember: World generation can take a few minutes. Be patient."
  echo