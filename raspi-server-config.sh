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
  # NOTE: it's tempting to redirect stderr to /dev/null, so supress error 
  # output from tput. However in this case, tput detects neither stdout or 
  # stderr is a tty and so only gives default 80, 24 values
  WT_HEIGHT=17
  WT_WIDTH=$(tput cols)

  if [ -z "$WT_WIDTH" ] || [ "$WT_WIDTH" -lt 60 ]; then
    WT_WIDTH=80
  fi
  if [ "$WT_WIDTH" -gt 178 ]; then
    WT_WIDTH=120
  fi
  WT_MENU_HEIGHT=$(($WT_HEIGHT-7))
}

do_about() {
  whiptail --msgbox "\
This tool provides a straight-forward way of doing initial
configuration of the Raspberry Pi. Although it can be run
at any time, some of the options may have difficulties if
you have heavily customised your installation.\
" 20 70 1
}

do_expand_rootfs() {
  get_init_sys
  if [ $SYSTEMD -eq 1 ]; then
    ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')
  else
    if ! [ -h /dev/root ]; then
      whiptail --msgbox "/dev/root does not exist or is not a symlink. Don't know how to expand" 20 60 2
      return 0
    fi
    ROOT_PART=$(readlink /dev/root)
  fi

  PART_NUM=${ROOT_PART#mmcblk0p}
  if [ "$PART_NUM" = "$ROOT_PART" ]; then
    whiptail --msgbox "$ROOT_PART is not an SD card. Don't know how to expand" 20 60 2
    return 0
  fi

  # NOTE: the NOOBS partition layout confuses parted. For now, let's only 
  # agree to work with a sufficiently simple partition layout
  if [ "$PART_NUM" -ne 2 ]; then
    whiptail --msgbox "Your partition layout is not currently supported by this tool. You are probably using NOOBS, in which case your root filesystem is already expanded anyway." 20 60 2
    return 0
  fi

  LAST_PART_NUM=$(parted /dev/mmcblk0 -ms unit s p | tail -n 1 | cut -f 1 -d:)
  if [ $LAST_PART_NUM -ne $PART_NUM ]; then
    whiptail --msgbox "$ROOT_PART is not the last partition. Don't know how to expand" 20 60 2
    return 0
  fi

  # Get the starting offset of the root partition
  PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^${PART_NUM}" | cut -f 2 -d: | sed 's/[^0-9]//g')
  [ "$PART_START" ] || return 1
  # Return value will likely be error for fdisk as it fails to reload the
  # partition table because the root fs is mounted
  fdisk /dev/mmcblk0 <<EOF
p
d
$PART_NUM
n
p
$PART_NUM
$PART_START

p
w
EOF
  ASK_TO_REBOOT=1

  # now set up an init.d script
cat <<EOF > /etc/init.d/resize2fs_once &&
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resize2fs_once
# Required-Start:
# Required-Stop:
# Default-Start: 3
# Default-Stop:
# Short-Description: Resize the root filesystem to fill partition
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "\$1" in
  start)
    log_daemon_msg "Starting resize2fs_once" &&
    resize2fs /dev/$ROOT_PART &&
    update-rc.d resize2fs_once remove &&
    rm /etc/init.d/resize2fs_once &&
    log_end_msg \$?
    ;;
  *)
    echo "Usage: \$0 start" >&2
    exit 3
    ;;
esac
EOF
  chmod +x /etc/init.d/resize2fs_once &&
  update-rc.d resize2fs_once defaults &&
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "Root partition has been resized.\nThe filesystem will be enlarged upon the next reboot" 20 60 2
  fi
}

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end

if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
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
  whiptail --msgbox "You will now be asked to enter a new password for the pi user" 20 60 1
  passwd pi &&
  whiptail --msgbox "Password changed successfully" 20 60 1
}

do_configure_keyboard() {
}

do_change_locale() {
}

do_change_timezone() {
}

do_change_hostname() {
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "\
Please note: RFCs mandate that a hostname's labels \
may contain only the ASCII letters 'a' through 'z' (case-insensitive), 
the digits '0' through '9', and the hyphen.
Hostname labels cannot begin or end with a hyphen. 
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

do_memory_split() {
}

get_current_memory_split() {
}

set_memory_split() {
}

do_overclock() {
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "\
Be aware that overclocking may reduce the lifetime of your
Raspberry Pi. If overclocking at a certain level causes
system instability, try a more modest overclock. Hold down
shift during boot to temporarily disable overclock.
See http://elinux.org/RPi_Overclocking for more information.\
" 20 70 1
    OVERCLOCK=$(whiptail --menu "Choose overclock preset" 20 60 10 \
      "None" "700MHz ARM, 250MHz core, 400MHz SDRAM, 0 overvolt" \
      "Modest" "800MHz ARM, 250MHz core, 400MHz SDRAM, 0 overvolt" \
      "Medium" "900MHz ARM, 250MHz core, 450MHz SDRAM, 2 overvolt" \
      "High" "950MHz ARM, 250MHz core, 450MHz SDRAM, 6 overvolt" \
      "Turbo" "1000MHz ARM, 500MHz core, 600MHz SDRAM, 6 overvolt" \
      "Pi2" "1000MHz ARM, 500MHz core, 500MHz SDRAM, 2 overvolt" \
      3>&1 1>&2 2>&3)
  else
    OVERCLOCK=$1
    true
  fi
  if [ $? -eq 0 ]; then
    case "$OVERCLOCK" in
      None)
        clear_overclock
        ;;
      Modest)
        set_overclock Modest 800 250 400 0
        ;;
      Medium)
        set_overclock Medium 900 250 450 2
        ;;
      High)
        set_overclock High 950 250 450 6
        ;;
      Turbo)
        set_overclock Turbo 1000 500 600 6
        ;;
      Pi2)
        set_overclock Pi2 1000 500 500 2
        ;;
      Pi2None)
        clear_overclock
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised overclock preset" 20 60 2
        return 1
        ;;
    esac
    ASK_TO_REBOOT=1
  fi
}

set_overclock() {
  set_config_var arm_freq $2 $CONFIG &&
  set_config_var core_freq $3 $CONFIG &&
  set_config_var sdram_freq $4 $CONFIG &&
  set_config_var over_voltage $5 $CONFIG &&
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "Set overclock to preset '$1'" 20 60 2
  fi
}

clear_overclock () {
  clear_config_var arm_freq $CONFIG &&
  clear_config_var core_freq $CONFIG &&
  clear_config_var sdram_freq $CONFIG &&
  clear_config_var over_voltage $CONFIG &&
  if [ "$INTERACTIVE" = True ]; then
    whiptail --msgbox "Set overclock to preset 'None'" 20 60 2
  fi
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
  get_init_sys
  if [ $SYSTEMD -eq 0 ]; then
    whiptail --msgbox "This option can only be selected when using systemd" 20 60 2
    return 1
  fi
  if [ "$INTERACTIVE" = True ]; then
    RET=$(whiptail --menu "Choose boot option" 20 70 10 \
      "Fast" "Boot without waiting for network connection" \
      "Slow" "Wait for network connection before completing boot" \
      3>&1 1>&2 2>&3)
  else
    get_init_sys
    RET=$1
    true
  fi
  if [ $? -eq 0 ]; then
    case "$RET" in
      Fast)
        rm /etc/systemd/system/dhcpcd.service.d/wait.conf
        ;;
      Slow)
        mkdir -p /etc/systemd/system/dhcpcd.service.d/
        cat > /etc/systemd/system/dhcpcd.service.d/wait.conf << EOF
[Service]
ExecStart=
ExecStart=/sbin/dhcpcd -q -w
EOF
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised option" 20 60 2
        return 1
        ;;
    esac
  fi
}

do_boot_behaviour() {
  if [ "$INTERACTIVE" = True ]; then
    BOOTOPT=$(whiptail --menu "Choose boot option" 20 60 10 \
      "Console" "Text console, requiring login (default)" \
      "Desktop" "Log in as user 'pi' at the graphical desktop" \
      3>&1 1>&2 2>&3)
  else
    get_init_sys
    BOOTOPT=$1
    true
  fi
  if [ $? -eq 0 ]; then
    case "$BOOTOPT" in
      Console)
        if [ -e /etc/init.d/lightdm ]; then
          if [ $SYSTEMD -eq 1 ]; then
            systemctl set-default multi-user.target
          else
            update-rc.d lightdm disable 2
          fi
        fi
        ;;
      Desktop)
        if [ -e /etc/init.d/lightdm ]; then
          if id -u pi > /dev/null 2>&1; then
            if [ $SYSTEMD -eq 1 ]; then
              systemctl set-default graphical.target
            else
              update-rc.d lightdm enable 2
            fi
            sed /etc/lightdm/lightdm.conf -i -e "s/^#autologin-user=.*/autologin-user=pi/"
            disable_raspi_config_at_boot
          else
            whiptail --msgbox "The pi user has been removed, can't set up boot to desktop" 20 60 2
          fi
        else
          whiptail --msgbox "Do sudo apt-get install lightdm to allow configuration of boot to desktop" 20 60 2
          return 1
        fi
        ;;
      *)
        whiptail --msgbox "Programmer error, unrecognised boot option" 20 60 2
        return 1
        ;;
    esac
    ASK_TO_REBOOT=1
  fi
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
