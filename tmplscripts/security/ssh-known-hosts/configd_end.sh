#!/opt/vyatta/bin/cliexec
>| /etc/ssh/ssh_known_hosts
for h in $VAR(./host/@@); do
    k=$(cli-shell-api returnValue security ssh-known-hosts host $h key)
    if [[ -n "$k" ]]; then
	echo "$h" $k >> /etc/ssh/ssh_known_hosts
    fi
done

# link to a location that can be read by non-root users of vyatta-curl-wrapper
install -d -o root -g root -m 755 /run/ssh/curl_home/.ssh
ln -sf /etc/ssh/ssh_known_hosts /run/ssh/curl_home/.ssh/known_hosts

# retain old link to avoid breakage.
hdir=$(getent passwd root | cut -d: -f6)
install -d -o root -g root -m 700 $hdir/.ssh
ln -sf /etc/ssh/ssh_known_hosts $hdir/.ssh/known_hosts
