#!/bin/sh
# Part of raspi-config https://github.com/RPi-Distro/raspi-config
#
# See LICENSE file for copyright and license details

INTERACTIVE=True
ASK_TO_REBOOT=0
BLACKLIST=/etc/modprobe.d/raspi-blacklist.conf
CONFIG=/boot/config.txt

get_init_sys() {
  if command -v systemctl > /dev/null && systemctl | grep -q '\-\.mount'; then
    SYSTEMD=1
  elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
    SYSTEMD=0
  else
    echo "Unrecognised init system"
    return 1
  fi
}

calc_wt_size() {
}

do_about() {
  whiptail --msgbox "\
This tool provides a straight-forward way of doing initial
configuration of the Raspberry Pi. Although it can be run
at any time, some of the options may have difficulties if
you have heavily customised your installation.\
" 20 70 1
}

do_set_ip() {
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "\
Please note: RFCs mandate that a hostname's labels \
may contain only the ASCII letters 'a' through 'z' (case-insensitive), 
the digits '0' through '9', and the hyphen.
No other symbols, punctuation characters, or blank spaces are permitted.\
" 20 70 1
  fi
  CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
  if [ "$INTERACTIVE" = True ]; then
    NEW_HOSTNAME=$(whiptail --inputbox "Please enter a hostname" 20 60 "$CURRENT_HOSTNAME" 3>&1 1>&2 2>&3)
  else
    NEW_HOSTNAME=$1
    true
  fi
  if [ $? -eq 0 ]; then
    echo $NEW_HOSTNAME > /etc/hostname
    sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
    ASK_TO_REBOOT=1
  fi



}

clear_config_var() {
  lua - "$1" "$2" <<EOF > "$2.bak"
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
  if line:match("^%s*"..key.."=.*$") then
    line="#"..line
  end
  print(line)
end
EOF
mv "$2.bak" "$2"
}

get_config_var() {
  lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
local found=false
for line in file:lines() do
  local val = line:match("^%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    found=true
    break
  end
end
if not found then
   print(0)
end
EOF
}

# $1 is 0 to disable overscan, 1 to disable it
set_overscan() {
}

do_overscan() {
}

do_change_pass() {
}

do_configure_keyboard() {
}

do_change_locale() {
}

do_change_timezone() {
}

do_change_hostname() {
}

do_memory_split() {
}

get_current_memory_split() {
}

set_memory_split() {
}

do_overclock() {
}

set_overclock() {
}

do_ssh() {
  if [ -e /var/log/regen_ssh_keys.log ] && ! grep -q "^finished" /var/log/regen_ssh_keys.log; then
    whiptail --msgbox "Initial ssh key generation still running. Please wait and try again." 20 60 2
    return 1
  fi
  if [ "$INTERACTIVE" = True ]; then
    whiptail --yesno "Would you like the SSH server enabled or disabled?" 20 60 2 \
      --yes-button Enable --no-button Disable
    RET=$?
  else
    RET=$1
  fi
  if [ $RET -eq 0 ]; then
    update-rc.d ssh enable &&
    invoke-rc.d ssh start &&
    if [ "$INTERACTIVE" = True ]; then
      whiptail --msgbox "SSH server enabled" 20 60 1
    fi
  elif [ $RET -eq 1 ]; then
    update-rc.d ssh disable &&
    if [ "$INTERACTIVE" = True ]; then
      whiptail --msgbox "SSH server disabled" 20 60 1
    fi
  else
    return $RET
  fi
}

do_devicetree() {
}

do_spi() {
}

do_i2c() {
}

do_serial() {
}

disable_raspi_config_at_boot() {
  if [ -e /etc/profile.d/raspi-config.sh ]; then
    rm -f /etc/profile.d/raspi-config.sh
    if [ $SYSTEMD -eq 1 ]; then
      if [ -e /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf ]; then
        rm /etc/systemd/system/getty@tty1.service.d/raspi-config-override.conf
      fi
    else
      sed -i /etc/inittab \
        -e "s/^#\(.*\)#\s*RPICFG_TO_ENABLE\s*/\1/" \
        -e "/#\s*RPICFG_TO_DISABLE/d"
    fi
    telinit q
  fi
}

do_boot_behaviour_new() {
}

do_wait_for_network() {
}

do_boot_behaviour() {
}

do_rastrack() {
}

set_camera() {
}

do_camera() {
}


set_gldriver() {
}

do_gldriver() {
}

do_update() {
  apt-get update &&
  apt-get install raspi-config &&
  printf "Sleeping 5 seconds before reloading raspi-config\n" &&
  sleep 5 &&
  exec raspi-config
}

do_audio() {
}

do_finish() {
  disable_raspi_config_at_boot
  if [ $ASK_TO_REBOOT -eq 1 ]; then
    whiptail --yesno "Would you like to reboot now?" 20 60 2
    if [ $? -eq 0 ]; then # yes
      sync
      reboot
    fi
  fi
  exit 0
}

nonint() {
    $*
}

#
# Command line options for non-interactive use
#
for i in $*
do
  case $i in
  --memory-split)
    OPT_MEMORY_SPLIT=GET
    printf "Not currently supported\n"
    exit 1
    ;;
  --memory-split=*)
    OPT_MEMORY_SPLIT=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
    printf "Not currently supported\n"
    exit 1
    ;;
  --expand-rootfs)
    INTERACTIVE=False
    do_expand_rootfs
    printf "Please reboot\n"
    exit 0
    ;;
  --apply-os-config)
    INTERACTIVE=False
    do_apply_os_config
    exit $?
    ;;
  nonint)
    INTERACTIVE=False
    $@
    ;;
  *)
    # unknown option
    ;;
  esac
done

#if [ "GET" = "${OPT_MEMORY_SPLIT:-}" ]; then
#  set -u # Fail on unset variables
#  get_current_memory_split
#  echo $CURRENT_MEMSPLIT
#  exit 0
#fi

# Everything else needs to be run as root
if [ $(id -u) -ne 0 ]; then
  printf "Script must be run as root. Try 'sudo raspi-config'\n"
  exit 1
fi

if [ -n "${OPT_MEMORY_SPLIT:-}" ]; then
  set -e # Fail when a command errors
  set_memory_split "${OPT_MEMORY_SPLIT}"
  exit 0
fi

do_internationalisation_menu() {
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Internationalisation Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "I1 Change Locale" "Set up language and regional settings to match your location" \
    "I2 Change Timezone" "Set up timezone to match your location" \
    "I3 Change Keyboard Layout" "Set the keyboard layout to match your keyboard" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      I1\ *) do_change_locale ;;
      I2\ *) do_change_timezone ;;
      I3\ *) do_configure_keyboard ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
}

do_monitoring_tools() {
  FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Install Monitoring Tools" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Back --ok-button Select \
    "A1 "RPi-Monitor" "" \
    "A2 "Raspcontrol" \
    "A3 " \
    "A4 " \
    "A5 " \
    "A6 " \
    "A7 " \
    "A8 " \
    "A9 " \
    "AA " \
    "A0 Update" "Update this tool to the latest version" \
    3>&1 1>&2 2>&3)
  RET=$?
  if [ $RET -eq 1 ]; then
    return 0
  elif [ $RET -eq 0 ]; then
    case "$FUN" in
      A1\ *) do_rpi_monitor ;;
      A2\ *) do_raspcontrol ;;
      A3\ *) do_ ;;
      A4\ *) do_ssh ;;
      A5\ *) do_devicetree ;;
      A6\ *) do_spi ;;
      A7\ *) do_i2c ;;
      A8\ *) do_serial ;;
      A9\ *) do_audio ;;
      AA\ *) do_gldriver ;;
      A0\ *) do_update ;;
      *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
    esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
  fi
}


#
# Interactive use loop
#
if [ "$INTERACTIVE" = True ]; then
  get_init_sys
  calc_wt_size
  while true; do
    FUN=$(whiptail --title "Raspberry Pi Software Configuration Tool (raspi-config)" --menu "Setup Options" $WT_HEIGHT $WT_WIDTH $WT_MENU_HEIGHT --cancel-button Finish --ok-button Select \
      "1 Set Dynamic or Static IP Adress" \
      "2 Remove Desktop Packeges" \
      "3 Enable custom SSH Login MEssage (MOTD)" \
      "4 Install Monitoring Tools" \
      "5 " \
      "6 " \
      "7 " \
      "8 " \
      "9 " \
      "0 About raspi-config" "Information about this configuration tool" \
      3>&1 1>&2 2>&3)
    RET=$?
    if [ $RET -eq 1 ]; then
      do_finish
    elif [ $RET -eq 0 ]; then
      case "$FUN" in
        1\ *) do_set_ip ;;
        2\ *) do_remove_desktop ;;
        3\ *) do_custom_MOTD ;;
        4\ *) do_monitoring_tools ;;
        5\ *)  ;;
        6\ *)  ;;
        7\ *)  ;;
        8\ *)  ;;
        9\ *)  ;;
        0\ *) do_about ;;
        *) whiptail --msgbox "Programmer error: unrecognized option" 20 60 1 ;;
      esac || whiptail --msgbox "There was an error running option $FUN" 20 60 1
    else
      exit 1
    fi
  done
fi
