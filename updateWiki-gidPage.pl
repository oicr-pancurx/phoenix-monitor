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

#https://pinery.hpc.oicr.on.ca:8443/pinery/samples?type=Identity
#my $limsUrl = "https://pinery.hpc.oicr.on.ca:8443/pinery/";
my $limsUrl = "http://pinery.gsi.oicr.on.ca:8080/pinery-ws-miso/";

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content/92537448";
my $wikiID = 92537448;

my $l;
my @f;


my %json;
my %summaryData;

my $url;


my %printIDs = (
	"PCSI" => 1,
	"ASHPC" => 1,
	"RAMP" => 1,
	"BTC" => 1,
);

my $prettyJson;

my $samplesRef;
warn "\n Starting sample hierarchy download\n";
if ($doTest == 0)
{
#	$prettyJson = `curl -X GET http://pinery.gsi.oicr.on.ca:8080/pinery-ws-miso/samples`;
	$prettyJson = `curl -X GET http://pinery-prod.hpc.oicr.on.ca:8080/pinery-ws-miso/samples`;
	$prettyJson =~ s/\n//g;
	$samplesRef = decode_json($prettyJson);
}
else
{
	$prettyJson = `cat t2`;
	$prettyJson =~ s/\n//g;
	$samplesRef = decode_json($prettyJson);
}
warn " Finished sample hierarhcy download\n\n";

my %data;

my ($tisURL,$tisName,$tisType,$tisCreate,$extURL,$extName,$extType,$extCreate,$alqURL,$alqName,$alqType,$alqCreate,$libURL,$libName,$libType,$libCreate,$seqURL,$seqName,$seqType,$seqCreate);
my ($capURL,$capName,$capType,$capCreate);

warn " Converting sample hierarchy into json\n";
for (my $i = 0; $i < scalar(@$samplesRef); $i++)
{
	$json{$samplesRef->[$i]{url}} = $samplesRef->[$i];
}

$samplesRef = "";		# free some ram, ideally (it does not)

my ($prefix,$name,$externalName, $tissue, $type, $institute);
my $otherID;

my %gidHash;
my $gid;
my $desc;

warn " Parsing sample hierarchy\n";
for my $url (keys %json)
{
	$prefix = "";
	$name = $json{$url}{name};
	$gid = "";
	$desc = "";


	if ($name =~ /(^.*?)_(.*?_.*?_.*?)_/)
	{
		$prefix = $1;
		$name = $1 . "_" . $2;
	}

	if (exists $printIDs{$prefix})
	{

		if (exists $json{$url}{attributes})
		{
			for (my $j = 0; $j <= $#{ $json{$url}{attributes} }; $j++)
			{
				if ($json{$url}{attributes}[$j]{name} eq "Group ID")
				{
					$gid = $json{$url}{attributes}[$j]{value};
				}
				if ($json{$url}{attributes}[$j]{name} eq "Group Description")
				{
					$desc = $json{$url}{attributes}[$j]{value};
				}
			}
		}

		unless ($gid eq "")
		{
			$gidHash{"$name$gid"}{name} = $name;
			$gidHash{"$name$gid"}{gid} = $gid;
			$gidHash{"$name$gid"}{desc} = $desc;
		}
	}

}

%json = ();		# frees ram, ideally


warn "  Printing table\n";
# print table
print "Sample,Group ID,Description\n";
for $name (sort keys %gidHash)
{
	print "$gidHash{$name}{name},$gidHash{$name}{gid},$gidHash{$name}{desc}\n";
}


# push to wiki

my $page;
my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

open (OLD, "updateWiki-gidPage.oldPage") or die "Couldn't open updateWiki-gidPage.oldPage\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;

$page .= "<table><tbody>";
$page .= "<tr><th style=\\\"text-align: center;\\\">Sample</th><th style=\\\"text-align: center;\\\">Group ID</th><th style=\\\"text-align: center;\\\">Description</th></tr>";


for $name (sort keys %gidHash)
{

	$page .= "<tr><td><strong>$gidHash{$name}{name}</strong></td><td>$gidHash{$name}{gid}</td><td>$gidHash{$name}{desc}</td>";
	$page .= "</tr>";
}
$page .= "</tbody></table>";

unless ($page eq $oldPage)
{
	open (FILE, ">gid.curl") or die "Couldn't open >gid.curl\n";
	print FILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"Group ID List\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}\n";
	close FILE;

	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d\@gid.curl $wikiURL`);



#	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{"id":"$wikiID","type":"page","title":"Group ID List","space":{"key":"PanCuRx"},"body":{"storage":{"value":"$page","representation":"storage"}}, "version":{"number":$pageVersion}}' $wikiURL`);


#	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"Group ID List\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}' $wikiURL";

	open (OLD, ">updateWiki-gidPage.oldPage") or die "Couldn't open updateWiki-gidPage.oldPage\n";
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

	return "$year-$month-$day";
}



