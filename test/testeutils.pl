#!/usr/bin/env perl
# Script for testing EUtils JSON output
# All output files will be written to an "out" subdirectory here.

# Right now this only tests esummary IDX databases, using the DTDs that are
# in a working copy of the subversion repo.

use strict;
use warnings;
use EutilsTest;
use Data::Dumper;
use Getopt::Long;
use File::Which;
use File::Copy;


# Create a new test object, and read in the testcases.xml file
my $t = EutilsTest->new();
my $samplegroups = $t->{samplegroups};
#print Dumper($samplegroups);

my %Opts;
my $ok = GetOptions(\%Opts,
    "help|?",
    "quiet",
    "continue-on-error",
    "reset",
    "tld:s",
    "eutil:s",
    "db:s",
    "dtd:s",
    "sample:s",
    "idx",
    "error",
    @EutilsTest::steps,
    "xml-docsumtool:s",
    "dbinfo:s",
    "build:s",
    "xslt-loc:s",
    "pipe-basic",
    "pipe-qa-monitor",
    "pipe-qa-release",
    "pipe-cidx-verify",
    "pipe-idx-svn",
);
#print Dumper \%Opts;

my $usage = q(
Usage:  testeutils.pl [options] {step / pipeline}

This script tests EUtilities, using some subset of the test cases defined
in the samples.xml file.  At least one step or pipeline must be given.

Options to control the steps to test.  At least one step, or at least one
pipeline, must be given.
) .
(join("", map { "  --$_\n" } @EutilsTest::steps)) .
q(
  --dtd-remote - Leave the DTD on the remote server, rather than copying it
    locally.
  --dtd-svn - Get the DTDs from svn instead of the system identifier.  Only
    works with --idx.  Can't be used with other --dtd options.
  --dtd-oldurl - Use old-style URLs to get the DTDs; prior to the redesign
    of the system and public identifiers.
  --dtd-doctype - Trust the doctype declaration.  Can be used in conjunction
    with --tld or with --dtd-remote.  This won't do any checking to see that
    the doctype decl matches what we expect, or that every sample in a group
    has the same doctype decl.
  --dtd-loc=<full-path-to-dtd> - Specify the location of the DTD explicitly.
    This should only be used when testing just one samplegroup at a time.

Other options:
  --xml-docsumtool=<path-to-tool> - When testing CIDX pipeline, we use a utility
    to generate docsums, that we then wrap into an XML file
  --dbinfo - Location of the dbinfo.ini file.  Same as for CIDX tools; this is
    passed to the xml-docsumtool
  --build - Build identfier.  Same as for CIDX tools; this is passed to the
    xml-docsumtool
  --xslt-loc - Specify the location of the XSLT explicitly.  This is used in
    conjunction with --dtd-loc, when testing just one samplegroup at a time.

Pipelines.  These are shorthands for collections of other options.  At least
one pipeline, or at least one step, must be given.
  --pipe-basic
  --pipe-qa-monitor
  --pipe-qa-release
  --pipe-cidx-verify
  --pipe-idx-svn
);

if ($Opts{help}) {
    print $usage;
    exit 0;
}

# Pipelines are collections of other options, that will get merged in
my %pipelines = (
    'basic' => {
        'fetch-dtd' => 1,
        'fetch-xml' => 1,
        'validate-xml' => 1,
        'generate-xslt' => 1,
        'generate-json' => 1,
        'validate-json' => 1,
    },
    'qa-monitor' => {
        'reset' => 1,
        'idx' => 1,
        'eutil' => 'esummary',
        'fetch-dtd' => 1,
        'fetch-xml' => 1,
        'validate-xml' => 1,
        'fetch-json' => 1,
        'validate-json' => 1,
    },
    'qa-release' => {
        'reset' => 1,
        'tld' => 'qa',
        'eutil' => 'esummary',
        'fetch-dtd' => 1,
        'fetch-xml' => 1,
        'validate-xml' => 1,
        'fetch-json' => 1,
        'validate-json' => 1,
    },
    'cidx-verify' => {
        'reset' => 1,
        'eutil' => 'esummary',
        'fetch-dtd' => 1,
        'generate-xml' => 1,
        'validate-xml' => 1,
        'generate-xslt' => 1,
        'generate-json' => 1,
        'validate-json' => 1,
    },
    'idx-svn' => {
        'reset' => 1,
        'idx' => 1,
        'eutil' => 'esummary',
        'fetch-dtd' => 1,
        'fetch-xml' => 1,
        'validate-xml' => 1,
        'generate-xslt' => 1,
        'generate-json' => 1,
        'validate-json' => 1,
    }
);

# If no pipeline and no steps are selected, then use pipe-default.
my $pipeline = $Opts{'pipe-basic'} ? 'basic' :
               $Opts{'pipe-qa-monitor'} ? 'qa-monitor' :
               $Opts{'pipe-qa-release'} ? 'qa-release' :
               $Opts{'pipe-cidx-verify'}    ? 'cidx-verify' :
               $Opts{'pipe-idx-svn'}    ? 'idx-svn' : '';

# This will be true if any of the step options was given
my $stepOptGiven = grep { $Opts{$_} } @EutilsTest::steps;

if (!$pipeline && !$stepOptGiven) {
    print $usage;
    exit 0;
}

# Merge in the pipeline options
my $pipeOpts = $pipelines{$pipeline};
foreach my $k (keys %$pipeOpts) {
    $Opts{$k} = $pipeOpts->{$k};
}
#print Dumper \%Opts;





my $xmlDocsumTool = $Opts{'xml-docsumtool'};
my $dbinfo = $Opts{'dbinfo'};
my $build = $Opts{'build'};
my $xsltLoc = $Opts{'xslt-loc'};

# Set things up


if (!$Opts{quiet}) {
    if ($pipeline) {
        print "Executing pipeline '$pipeline'\n";
    }
    else {
        print "Executing discrete steps\n";
    }
}

# Now run the tests, for each sample group, ...
foreach my $sg (@$samplegroups) {


    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    next if !$t->fetchDtd($sg, $doFetchDtd, $dtdRemote, $tld, $dtdSvn,
                          $dtdDoctype, $dtdOldUrl, $dtdLoc);
    $log->indent;

    # For each sample corresponding to this DTD:
    foreach my $s (@$groupsamples) {
        next if !sampleMatch($s);

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        if ($doGenerateXml) {
            next if !$t->generateXml($s, $doGenerateXml, $xmlDocsumTool,
                                     $dbinfo, $build);
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        if ($doFetchXml) {
            next if !$t->fetchXml($s, $doFetchXml, $tld);
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        $log->indent;
        $t->validateXml($s, $doValidateXml, $s->{'local-xml'}, $dtdRemote, $tld,
                        $dtdDoctype);
        $log->undent;
    }

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    if (!$t->generateXslt($sg, $doGenerateXslt, $xsltLoc)) {
        $log->undent;
        next;
    }
    my $jsonXsltPath = $sg->{'json-xslt'};
    $log->indent;

    # Now, for each sample, generate the JSON output
    foreach my $s (@$groupsamples) {
        next if !sampleMatch($s);

        if ($doGenerateJson) {
            if ($s->{failure}{'fetch-xml'}) {
                $log->message("Skipping generate-json for " . $s->{name} .
                              ", because fetch-xml failed");
                next;
            }

            # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            next if !$t->generateJson($s, $doGenerateJson);
        }

        else {
            # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            next if !$t->fetchJson($s, $doFetchJson, $tld);
        }

        # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        $log->indent;
        $t->validateJson($s, $doValidateJson);
        $log->undent;
    }

    $log->undent;
    $log->undent;
}

# Summary pass / fail report
if ($t->{failures}) {
    print $t->{failures} . " failures:\n";
    foreach my $sg (@$samplegroups) {
        if ($sg->{failure}) {
            print "  " . $sg->{dtd} . ": ";
            my @fs = map { $sg->{failure}{$_} ? $_ : () } @EutilsTest::steps;
            print join(", ", @fs) . "\n";
        }
    }
}
else {
    print "All tests passed!\n";
}
exit !!$t->{failures};


