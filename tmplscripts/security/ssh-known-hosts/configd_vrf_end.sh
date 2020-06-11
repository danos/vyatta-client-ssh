#!/opt/vyatta/bin/cliexec

# There are two locations to create ssh-known-host keys
# set security ssh-known-host
# set routing routing-instance blue security ssh-known-host
#
# When setting 'set service ssh-known-host' we set the known host file for the
# management vrf.
#
# THIS SETS THE GLOBAL KNOWN HOST FILE FOR A VRF!

VRFName=$VAR(../../../routing-instance/@)
if [[ -z $VRFName ]]; then
    # Must be default (i.e. set security ssh-known-hosts 192.168...)
    VRFName='default'
fi

case $COMMIT_ACTION in
    DELETE)
        rm -f /run/ssh/vrf/$VRFName/ssh_known_hosts
        rm -rf /run/ssh/vrf/$VRFName/curl_home
        ;;

    *)
        if [[ $VRFName == "default" ]]; then
            IFS=' ' read -a hosts <<< '$VAR(./host/@@)'
            for h in "${hosts[@]}"; do
                k=$(cli-shell-api returnValue security ssh-known-hosts host "$h" key)
                if [[ -n "$k" ]]; then
                    mkdir -p /run/ssh/vrf/$VRFName
                    echo "$h" "$k" >> /run/ssh/vrf/$VRFName/ssh_known_hosts
                fi
            done
        else
            IFS=' ' read -a hosts <<< '$VAR(./host/@@)'
            for h in "${hosts[@]}"; do
                k=$(cli-shell-api returnValue routing routing-instance $VRFName security ssh-known-hosts host "$h" key)
                if [[ -n "$k" ]]; then
                    mkdir -p /run/ssh/vrf/$VRFName
                    echo "$h" "$k" >> /run/ssh/vrf/$VRFName/ssh_known_hosts
                fi
            done
        fi
        mkdir -p /run/ssh/vrf/$VRFName/curl_home/.ssh
        ln -sf /run/ssh/vrf/$VRFName/ssh_known_hosts /run/ssh/vrf/$VRFName/curl_home/.ssh/known_hosts
        chmod -R a+rx /run/ssh/vrf/$VRFName/curl_home
        ;;
esac
