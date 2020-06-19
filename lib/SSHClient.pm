#! /usr/bin/perl
#
# Copyright (c) 2020, AT&T Intellectual Property. All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

package Vyatta::SSHClient;

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Readonly;

use parent 'Exporter';

our @EXPORT =
  qw($SSH_KNOWN_HOSTS @SSH_KEY_TYPES ssh_get_fingerprint ssh_key_select
  ssh_get_line ssh_get_host_to_delete ssh_delete_config ssh_set_config);

our $SSH_KNOWN_HOSTS = '/etc/ssh/ssh_known_hosts';

# Curl does not support ECDSA, and DSA is not recommended
our @SSH_KEY_TYPES = ( "RSA", "ED25519" );

sub ssh_get_fingerprint {
    my $key_entry = shift;

    # Fingerprint fmt: <key length> <fingerprint str> <host hash> (<KEY TYPE>)
    my $fingerprint = qx(echo '$key_entry' | ssh-keygen -qlf -);
    my ( $fp_str, $fp_key_type, $fp_hash ) =
      ( split / /, $fingerprint )[ 1, 3, 2 ];
    $fp_key_type =~ s/[()\n]+//g;

    return ( $fp_str, $fp_key_type, $fp_hash );
}

# Returns the selected key entry if found, so that config for this can be set.
# If a conflicting stored key entry needs to be deleted, then the stored
# fingerprint string and key type are also returned.
sub ssh_key_select {
    my ( $known_hosts_file, $host, @key_entries ) = @_;

    # Map of key type (e.g. RSA & ED25519 as shown in fingerprint) to key entry
    # Key entry fmt: <hash> <key type (e.g. ssh-rsa & ssh-ed25519)> <pub key>
    my %key_entries_map;
    foreach (@key_entries) {
        my $key_type = ( split / /, $_ )[1];
        $key_type =~ s/ssh-//;
        $key_type =~ s/-.*//;
        $key_entries_map{ uc($key_type) } = $_;
    }

    # The key type of entries may not be in the same order as requested
    my $key_entry;
    foreach (@SSH_KEY_TYPES) {
        $key_entry = $key_entries_map{$_};
        last if defined $key_entry;
    }

    # Legacy load-file expects a file with a single entry, but using cfg'd host
    my $stored_fingerprint;
    if ( -f $known_hosts_file ) {
        $stored_fingerprint =
          qx(ssh-keygen -q -l -F '$host' -f '$known_hosts_file');
    }

    return ( $key_entry, undef, undef ) unless $stored_fingerprint;

    # Stored fingerprint fmt: <host> <KEY TYPE> <fingerprint str>
    my ( $stored_fp_key_type, $stored_fp_str ) =
      ( split / /, $stored_fingerprint )[ 1, 2 ];
    my $found_entry = $key_entries_map{$stored_fp_key_type};
    my ( $fp_str, $fp_key_type );

    if ($found_entry) {
        ( $fp_str, $fp_key_type ) = ssh_get_fingerprint($found_entry);

        # Match stored key, no further action (curl will succeed)
        return ( undef, undef, undef ) if $fp_str eq $stored_fp_str;
    } else {
        foreach my $key_type ( keys %key_entries_map ) {
            if ( $key_type ne $stored_fp_key_type ) {
                $found_entry = $key_entries_map{$key_type};
                last;
            }
        }

        # No match or alternative found, no further action (curl will fail)
        return ( undef, undef, undef ) unless $found_entry;
    }
    return ( $found_entry, $stored_fp_str, $stored_fp_key_type );
}

sub ssh_get_line {
    my ( $loadfile, $linenum ) = @_;
    my $more;
    my $line;

    open( my $f, '<', $loadfile ) or return;
    while (<$f>) {
        if ( $. == $linenum ) {
            $line = $_;
            chomp($line);
            $more = 0;
        } elsif ( defined($more) ) {
            $more = 1;
            last;
        }
    }
    close $f;
    return ( $line, $more );
}

# Get stored hash or cleartext hostname/IP so as to delete from config.
# Retrieve entry again in case file updated while waiting at prompt.
# Rather than using just 'ssh-keygen -lF <host>', which always returns host in
# the clear, use this only to get the line number from the known hosts file,
# then retrieve this line, which is the key entry. Check that its fingerprint
# has not changed due to concurrent changes, then return stored hash from this.
sub ssh_get_host_to_delete {
    my ( $known_hosts_file, $host, $req_fp_str ) = @_;
    my $stored_fp = qx(ssh-keygen -l -f '$known_hosts_file' -F '$host');
    return unless $stored_fp =~ /(.*)found: line (\d+)\s+(\S+)\s(\S+)\s(\S+)/;

    my $linenum = $2;
    my $match_fp_str = $req_fp_str ? $req_fp_str : $5;
    my ($key_entry) = ssh_get_line( $known_hosts_file, $linenum );
    return unless $key_entry;

    my ( $fp_str, $fp_key_type, $fp_hash ) = ssh_get_fingerprint($key_entry);
    return ( "$fp_str" eq "$match_fp_str" ) ? $fp_hash : undef;
}

sub ssh_delete_config {
    my ( $cfg_client, $host, $rtdomain ) = @_;
    my @array;

    @array = ( "routing", "routing-instance", $rtdomain )
      if length( $rtdomain // '' );
    push( @array, ( "security", "ssh-known-hosts", "host", $host ) );
    $cfg_client->delete( \@array );
    return;
}

sub ssh_set_config {
    my ( $cfg_client, $host, $key_type, $pub_key, $rtdomain ) = @_;
    my @array;

    @array = ( "routing", "routing-instance", $rtdomain )
      if length( $rtdomain // '' );
    push(
        @array,
        (
            "security", "ssh-known-hosts",
            "host",     $host,
            "key",      "$key_type $pub_key"
        )
    );
    $cfg_client->set( \@array );
    return;
}

1;
