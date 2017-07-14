#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Time::Local;

my $doTest = 0;
if (exists $ARGV[0])
{
	if ($ARGV[0] eq "test")
	{
		$doTest = 1;
	}
}

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content/66970252";
my $wikiID = 66970252;

my $prefix = "/.mounts/labs/PCSI/analysis/oicr/";

my $phoenixCheckDate = 160910;

my $l;
my @f;

my @headers = qw/Donor Sample Updated QC/;
my @tests = qw/lanes collapsed json strelka\/v1.0.7 mutect\/1.1.4 final_strelka-mutect gatk\/1.3.16 final_gatk-germline crest\/alpha delly\/0.5.5 final_crest-delly HMMcopy\/0.1.1 celluloid\/v11.2 polysolver\/1.0 netMHC\/pan-2.8\/polysolver\/1.0 integration/;
my %qc;

my $ls = `ls $prefix/P*/*/wgs/*.qc.txt`;
chomp $ls;

my ($donor, $samp, $date, $tool, $result, $message);

for my $file (split(/\n/, $ls))
{
	if ($file =~ /$prefix.*?\/(PCSI....)\/(.*?)\/wgs/)
	{
		$donor = $1;
		$samp = $2;
	}
	$date = timeToYYMMDD( (stat($file))[9] );

	$qc{$samp}{donor} = $donor;
	$qc{$samp}{date} = $date;
	$qc{$samp}{qc} = "PASS";


	open (FILE, $file) or warn "Couldn't open $file\n";

	while ($l = <FILE>)
	{
		if ($l =~ /^(.*?) (.*?):(.*)$/)
		{
			$tool = $1;
			$result = $2;
			$message = $3;

			if ($result eq "WARN")
			{
				unless (($tool eq "strelka/v1.0.7") or ($tool eq "final_strelka-mutect"))		# skip these for now until the no somatic calls on chrY for ladies is handled better
				{
					unless (exists $qc{$samp}{$tool})
					{
						$qc{$samp}{$tool} = $result;
					}
					if ($qc{$samp}{qc} eq "PASS")
					{
						$qc{$samp}{qc} = $result;
					}
				}
			}
			else
			{
				$qc{$samp}{$tool} = $result;
				$qc{$samp}{qc} = $result;
			}
		}
	}

	close FILE;
}






# push to wiki

my $page;
my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

my $oldPageFile = "qcPCSI-Wiki.oldPage";
open (OLD, $oldPageFile) or die "Couldn't open $oldPageFile\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;

$page .= "<h2>PCSI QC Summary</h2>";

$page .= "<table><tbody>";
$page .= "<tr>";

for my $header (@headers)
{
	$page .= "<th style=\\\"text-align: center;\\\">$header</th>";
}

for my $test (@tests)
{
	$page .= "<th style=\\\"text-align: center;\\\">$test</th>";
}
$page .= "</tr>";


for my $samp (sort { $qc{$b}{date} <=> $qc{$a}{date} } keys %qc)
{
	$page .= "<tr>";
	$page .= "<td>$qc{$samp}{donor}</td>";
	$page .= "<td><strong>$samp</strong></td>";
	$page .= "<td>$qc{$samp}{date}</td>";

	if ($qc{$samp}{qc} eq "PASS")
	{
		$page .= "<td style=\\\"text-align: center;\\\"><ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image></td>";
	}
	elsif ($qc{$samp}{qc} eq "WARN")
	{
		$page .= "<td style=\\\"text-align: center;\\\"><ac:image><ri:attachment ri:filename=\\\"warning.png\\\"/></ac:image></td>";
	}
	if ($qc{$samp}{qc} eq "FAIL")
	{
		$page .= "<td style=\\\"text-align: center;\\\"><ac:image><ri:attachment ri:filename=\\\"error.png\\\"/></ac:image></td>";
	}

	for my $test (@tests)
	{
		if (exists $qc{$samp}{$test})
		{
			if ($qc{$samp}{$test} eq "WARN")
			{
				$page .= "<td style=\\\"text-align: center;\\\"><ac:image><ri:attachment ri:filename=\\\"warning.png\\\"/></ac:image></td>";
			}
			if ($qc{$samp}{$test} eq "FAIL")
			{
				$page .= "<td style=\\\"text-align: center;\\\"><ac:image><ri:attachment ri:filename=\\\"error.png\\\"/></ac:image></td>";
			}
		}
		else
		{
			$page .= "<td></td>";
		}
	}
	$page .= "</tr>";
}

$page .= "</tbody></table>";




unless ($page eq $oldPage)
{
	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"QC Report\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}' $wikiURL";

	open (FILE, ">qcPCSI-Wiki.curl") or die "Couldn't open >qcPCSI-Wiki.curl\n";
	print FILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"QC Report\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}\n";
	close FILE;

	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d\@qcPCSI-Wiki.curl $wikiURL`);

	open (OLD, ">$oldPageFile") or die "Couldn't open $oldPageFile\n";
	print OLD "$page\n";
	close OLD;
}
else
{
	print "skipping upload: page did not change\n";
}







sub timeToYYMMDD
{
	my $time = shift;

	$time = localtime($time);

	my %mon = qw/Jan 01 Feb 02 Mar 03 Apr 04 May 05 Jun 06 Jul 07 Aug 08 Sep 09 Oct 10 Nov 11 Dec 12/;

	$time =~ /... (...) *(.*?) ..:..:.. 20(..)/;

	my $month = $mon{$1};
	my $day = $2;
	if (length($day) == 1)
	{
		$day = "0$day";
	}
	my $year = $3;

	return "$year$month$day";
}



