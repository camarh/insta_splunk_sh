#!/bin/bash

# Make sure of having sudo rights
if [ $(id -u) -eq 0 ]; then


    es_url="https://www.splunk.com/en_us/download/splunk-enterprise.html"                                                   # Interesting website
    res=`curl -s --connect-timeout 10 --max-time 10 $es_url`                                                                # Request

    package_link=`echo $res | egrep -o 'data-link="\S+rpm' | cut -c12-`                                                   # Target url
    package_file=`echo $package_link | egrep -o "splunk-.+rpm"`                                                             # Target package_link
    latest_package_version=`echo $package_link | egrep -o "splunk-[0-9.]+"`                                                 # Set found package_link as last version

    check_splunk=`echo $(rpm -q splunk) | egrep -o "splunk-[0-9.]+"`                                                        # Check if Splunk is on the System
    if [ $? == 0 ]; then

        # Nothing to do when latest already installed
        if [ "$check_splunk" == "$latest_package_version" ]; then
            echo -e "\nNothing to do - You have Splunk latest version ($check_splunk) \n"
            exit

        # Otherwise let the user have the possibility to decline the upgrade
        else

            read -p "
            It looks like there is an old version of Splunk installed on the system.

            Current version: $check_splunk
            Latest version: $latest_package_version

            Would you like to upgrade it ? (y or n) " upgrade_choice
            upgrade_choice_w=`echo $upgrade_choice | egrep -o "^[ynYN]$"`

            # Check the input filled by the user
            while [ -z ${upgrade_choice_w} ]; do

                read -p "
                Choice not included. Would you like to upgrade it ? (y or n) " upgrade_choice
                upgrade_choice_w=`echo $upgrade_choice | egrep -o "^[ynYN]$"`
            done

            # Process the Upgrade only when the user states it expressly
            upgrade_choice_y=`echo $upgrade_choice | egrep -o "^[yY]$"`
            if [ ${upgrade_choice_y} ]; then

                echo -e "\n\n... Splunk Enterprise upgrade in progress ...\n\n"
                wget -q $package_link                                                                                       # Download the package_link
                rpm -U --quiet $package_file                                                                                # Process the Upgrade
                /opt/splunk/bin/splunk start --accept-license --answer-yes                                                  # Start Splunk and accept the license

            else
                exit                                                                                                        # Exit when upgrade refused
            fi

        fi
 
    else                                                                                                                    # When any, process brand new install

        read -s -p "To login the Splunk platform, provide admin password : " admin_pass                                     # Ask to create the admin password to login platform
        echo -e "\n\n\n\n... Preparing the system ...\n"
        echo -e "\n... Splunk Enterprise install in progress ...\n\n"
        wget -q $package_link                                                                                               # Download the package_link
        chown splunkuser:splunkuser $package_link                                                                           # Handle the ownership of the newly downloaded package

        # Install package and start the program
        rpm -i --quiet $package_link 
        /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "$admin_pass"

    fi

    # Then stop the programme in order to handle miscellaneous administrative setup
    /opt/splunk/bin/splunk stop

    # [upgrade case] in order to guard against possible errors relating to pre-existing scripts for boot-start, lets found out if Splunk demon script exist
    check_boot_script=`echo $(find /etc/systemd/system -maxdepth 1 -name Splunkd.service)`

    if [ ${check_boot_script} ]; then
        /opt/splunk/bin/splunk disable boot-start
    fi
    
    # Now let systemd handle Splunk boot-start with user/group splunk
    /opt/splunk/bin/splunk enable boot-start -user splunk -group splunk -systemd-managed 1

    # Consider right/ownership for user splunk if we want to avoid ourselves some disaster when starting up the program
    chown -R splunk:splunk /opt/splunk
    /opt/splunk/bin/splunk start
    sleep 5

    # Indicate the trash vortex for the anymore useful package
    rm $package_file

    # Open/allow necessary ports/services
    firewall-cmd  --zone=public --permanent --add-service=http
    firewall-cmd  --zone=public --permanent --add-service=https
    firewall-cmd  --zone=public --permanent --add-port=8000/tcp

    # Anticipate logs from various network devices by forwarding their logs to a port other than 514 which is intended for the local device
    firewall-cmd --permanent --add-forward-port=port=514:proto=udp:toport=5514 
    firewall-cmd --add-masquerade
    firewall-cmd --reload

    # Print out the status to confirm that Splunk is up and running
    echo -e "\n\n$(/opt/splunk/bin/splunk status)\n\n"
 
    # Notify user end of task
    if [ ${upgrade_choice_y} ]; then
        echo -e "\n\nSplunk Enterprise has been upgraded\n\n"
        exit
    else
        echo -e "\n\nSplunk Enterprise has been installed\n\n"  
        exit
    fi

# Exit if no privileges and notify
else
 
    echo -e "\nPrivileges needed to run this script.\n"
	exit

fi
