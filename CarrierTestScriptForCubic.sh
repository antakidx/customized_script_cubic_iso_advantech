#!/bin/bash
# Settings for Ubuntu Live USB
#   account=ubuntu
#   pass=""
#   csvPartition=sda3
# Settings for Installed Ubuntu
#   account=advantech
#   pass=password
#   csvPartition=sda1
account=advantech-ubuntu
csvPartition=sda2

port="/dev/ttyUSB2"
lanA=/sys/class/net/eno2
lanB=/sys/class/net/eno1

# Collect serial number and model number from dmi table.
serial="$(dmidecode -s system-serial-number | sed 's/ //g')"
model="$(dmidecode -s system-product-name | sed 's/ //g')"

# Collect the MAC addresses, convert to upper case.
macA="$(cat $lanA/address | sed 's/://g')"
macA=${macA^^}
macB="$(cat $lanB/address | sed 's/://g')"
macB=${macB^^}

# Collect today's date
mfgDate=$(date +%m/%d/%Y)

# Generate report file names.
reportFile="/home/$account/$serial.txt"
tmpfile="/home/$account/temp.txt"

# Let the user re-run the test if needed.
testResult="R"
while [ "$testResult" = "R" ]
do
    clear
    echo "        Carrier UNO-2271G V2 test report" | tee "$reportFile"
    echo " "  | tee -a "$reportFile"
    echo " "  | tee -a "$reportFile"
    echo "This file is in the home folder called $serial.txt" | tee -a "$reportFile"
    echo "Copy it to a USB stick to print the IMEI and ICCID label." | tee -a "$reportFile"
    echo " "  | tee -a "$reportFile"
    echo "Test Account information" | tee -a "$reportFile"
    echo "  user:  $account"  | tee -a "$reportFile"
    echo " "  | tee -a "$reportFile"
    echo "Serial number: $serial"  | tee -a "$reportFile"
    echo " "  | tee -a "$reportFile"
    echo " "  | tee -a "$reportFile"

#######################
# Test LAN ports 
#######################

    echo "Make sure LAN ports are connected together with an ethernet cable"
    echo "Checking LAN ports..." | tee -a "$reportFile"
    echo " " 

    var1=$(ping -c 3 192.168.43.1 | grep "3 received")
    if [ "$var1" ]; then
	    echo "    *** LAN ports work! ***"  | tee -a "$reportFile"
    else
	    echo "    *** LAN ports FAILED! ***"  | tee -a "$reportFile"
	    echo "    Remember to connect an Ethernet cable between the LAN ports"  | tee -a "$reportFile"
    fi

    echo " "  | tee -a "$reportFile"

    echo " Sending AT commands to check the LTE card and SIM"
    echo "   AT"
    echo "   ATI"
    echo "   AT+GSN"
    echo "   AT+QCCID"
    echo " Collecting data (about 10 seconds)..."


# Save settings of current terminal to restore later
    original_settings="$(stty -g)"

# Kill background process and restore terminal when this shell exits
# trap 'set +e; kill "$bgPid">/dev/null; stty "$original_settings"' EXIT
    trap 'set +e; stty "$original_settings"' EXIT


# Set up serial port, append all remaining parameters from command line
    stty -F "$port" raw -echo 

# Send AT commands to modem and capture individual responses to 
# the report file.
#  - Capture the seiral output
#  - Send the AT command
#  - Wait for response
#  - Kill the capture so I can do it all again

#  Note: there is a timing issue with redirecting the port output
#        killing the background task for the redirection.
#        and the timing on when the modem responds.
#        The sleep statements below were trial and error.

    echo -n -e "AT\r" > "$port"
    sleep 1s
#######################
# Get card information.
#######################
    cat "$port" >"$tmpfile" & bgPid=$!
    echo -n -e "ati\r" > "$port"
    sleep 1s
    kill "$bgPid"
    sleep 2s
    cardInfo="$(cat $tmpfile | sed 's/OK//; s/^/  /g; s/^\r\n//g' )"
    echo "LTE Card information:" >> "$reportFile"
    echo "$cardInfo" >> "$reportFile"

#######################
# Get IMEI info
#######################
    cat "$port" >"$tmpfile" & bgPid=$!
    echo -n -e "AT+GSN\r" > "$port"
    sleep 1s
    kill "$bgPid"
    sleep 2s
    cp $tmpfile imei.txt
    imei="$(cat $tmpfile | sed 's/OK//' | tr -d '\r\n')"
    echo -e "LTE IMEI:\t$imei" >> "$reportFile"

#######################
# Get ICCID info
#######################
    cat "$port" >"$tmpfile" & bgPid=$!
    echo -n -e "AT+QCCID\r" > "$port"
    sleep 1s
    kill "$bgPid"
    sleep 2s
    cp $tmpfile iccid.txt
    iccid="$(cat $tmpfile | sed 's/OK//g; s/\+QCCID\://' | tr -d '\r\n ')"
    echo -e "SIM ICCID:\t$iccid" >> "$reportFile"


# Restore the terminal settings
    set +e; 
    stty "$original_settings"

# Change the ownership of the report file and remove excess information
    chown $account:$account "$reportFile"
    sed -i 's/OK//g; s/\+QCCID\://' "$reportFile"

    clear
    cat "$reportFile" 

    echo " "
    echo "Check the above results.  "
    echo "  Enter R to retest"
    echo "  Enter S if test was successful. Update CSV file"
    echo "  Enter F if test failed. Exit."
    echo "Enter (S,F): "
    read testResult
    testResult=${testResult^^}
done
#######################
# Generate CSV file on USB stick
#######################



# Get the mount point for a USB stick mounted in sda1
if [ $testResult == "S" ]; then
    #usb=$(lsblk -rno "name,mountpoint" | grep $csvPartition | awk '{print $2}')

    mount /dev/$csvPartition /mnt
    usb=/mnt
    
    if [ -z $usb ]; then
        echo "USB drive not found.  Skipping CSV creation"
    else

# If the file doesn't exist create it with headers. 
        csvFile="$usb/Carrier.csv"
        if [ ! -f $csvFile ]; then
            echo "Creating $csvFile"
            echo "Manufacturer, SN, Model, MAC A, MAC B, DATE, ICCID, IMEI" > $csvFile
        fi

#Write current information to the file.
        echo "Adding $serial to CSV file[$csvFile]"
        echo "\"Advantech\", \"$serial\", \"$model\", \"$macA\", \"$macB\", \"$mfgDate\", \"$iccid\", \"$imei\"" >>$csvFile
        cat  $csvFile | tail -n 2
    fi

    echo "Press <Enter> to exit"
    read var
fi

