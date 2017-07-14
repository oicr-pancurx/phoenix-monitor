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

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content/73204375";
my $wikiID = 73204375;

my $l;
my @f;


my %json;
my %summaryData;

my %instAbbrev = (
	"University Health Network" => "UHN",
	"Sheba Medical Center" => "SMC",
	"Sheba Medical Centre" => "SMC",
	"Mayo Clinic" => "Mayo",
	"Sunnybrook Health Sciences Centre" => "SHSC",
	"Kingston General Hospital" => "KGH",
	"Massachusetts General Hospital" => "MGH",
	"Ottawa Hospital Research Institute" => "OHRI",
	"Ottawa Hospital Research Institute " => "OHRI",
	"University of Nebraska Medical Center" => "UNMC",
	"St Josephs Health Centre (Toronto)" => "SJHC",
	"Ontario Institute for Cancer Research" => "OICR"
);

my $url;

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
	open (JSON, "samples_160229.json") or die "Couldn't open samples_160229.json\n";
	$samplesRef = decode_json(<JSON>);
	close JSON;
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

$samplesRef = "";		# free some ram, ideally

my ($name,$externalName, $tissue, $type, $institute);
my $otherID;


warn " Parsing sample hierarchy\n";
for my $url (keys %json)
{
	if ($json{$url}{sample_type} eq "Identity")
	{
		$name = $json{$url}{name};
		$tissue = "";
		$type = "";
		if ($name =~ /PCSI/)
		{
			if (exists $json{$url}{attributes})
			{
				for (my $j = 0; $j <= $#{ $json{$url}{attributes} }; $j++)
				{
					if ($json{$url}{attributes}[$j]{name} eq "External Name")
					{
						$data{$name}{external} = $json{$url}{attributes}[$j]{value};
					}
				}
			}
		
			$data{$name}{created} = $json{$url}{created_date};

			if (exists $json{$url}{children})
			{
				for (my $tisIter = 0; $tisIter <= $#{ $json{$url}{children} }; $tisIter++)
				{
					$tisURL = $json{$url}{children}[$tisIter]{url};
			
					$tisName = $json{$tisURL}{name};

					if ($tisName =~ /^(.*?)_(.*?)_(..)_(.)_.*$/)
					{
						$otherID = "${1}_$2";
						$tissue = $3;
						$type = $4;
					}
					else
					{
						warn "Couldn't parse tissue $tisName\n";
					}

					if (($otherID ne $name) and !($otherID =~ /^PCSI/))
					{
						$data{$name}{otherID}{$otherID}++;
					}

					if ($type eq "R")
					{
						$data{$name}{normal}{"${tissue}_$type"}++;
					}
					elsif ($tissue eq "Pa")
					{
						$data{$name}{primary}{"${tissue}_$type"}++;
					}
					else
					{
						$data{$name}{mets}{"${tissue}_$type"}++;
					}

					$institute = "";
					if (exists $json{$tisURL}{attributes})
					{
						for (my $j = 0; $j <= $#{ $json{$tisURL}{attributes} }; $j++)
						{
							if ($json{$tisURL}{attributes}[$j]{name} eq "Institute")
							{
								$institute = $json{$tisURL}{attributes}[$j]{value};
							}
						}
					}

					if (exists $instAbbrev{$institute})
					{
						$institute = $instAbbrev{$institute};
					}

					unless ($institute eq "")
					{
						$data{$name}{institute}{$institute}++;
					}

	
				}
			}
		}
	}
}

%json = ();		# frees ram, ideally


warn "  Printing table\n";
# print table
print "Donor,Other ID,External Id,External Institute,Normal Tissue,Primary Tissue,Other Tissue,First Received\n";
for $name (sort keys %data)
{
	for my $tis (qw/normal primary mets otherID institute/)
	{
		if (exists $data{$name}{$tis})
		{
			for my $type (sort keys %{ $data{$name}{$tis} })
			{
				$data{$name}{"$tis all"} .= "$type, ";
			}
			$data{$name}{"$tis all"} =~ s/, $//;
		}
		else
		{
			$data{$name}{"$tis all"} = "";
		}
	}

	$data{$name}{created} =~ s/T.*$//;

	print "$name,$data{$name}{'otherID all'},$data{$name}{external},$data{$name}{'institute all'},$data{$name}{'normal all'},$data{$name}{'primary all'},$data{$name}{'mets all'},$data{$name}{created}\n";
}



# push to wiki

my $page;
my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

open (OLD, "updateWiki-identityPage.oldPage") or die "Couldn't open updateWiki-identityPage.oldPage\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;

$page .= "<table><tbody>";
$page .= "<tr><th style=\\\"text-align: center;\\\">PCSI ID</th><th style=\\\"text-align: center;\\\">Other ID</th><th style=\\\"text-align: center;\\\">External ID</th><th style=\\\"text-align: center;\\\">External Institute</th><th style=\\\"text-align: center;\\\">Normal Tissue</th><th style=\\\"text-align: center;\\\">Primary Tissue</th><th style=\\\"text-align: center;\\\">Other Tissue</th><th style=\\\"text-align: center;\\\">First Received</th></tr>";


for $name (sort keys %data)
{

	$page .= "<tr><td><strong>$name</strong></td><td>$data{$name}{'otherID all'}</td><td>$data{$name}{external}</td><td>$data{$name}{'institute all'}</td><td>$data{$name}{'normal all'}</td><td>$data{$name}{'primary all'}</td><td>$data{$name}{'mets all'}</td><td>$data{$name}{created}</td>";
	$page .= "</tr>";
}
$page .= "</tbody></table>";

unless ($page eq $oldPage)
{
	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{"id":"$wikiID","type":"page","title":"PCSI Identity Page","space":{"key":"PanCuRx"},"body":{"storage":{"value":"$page","representation":"storage"}}, "version":{"number":$pageVersion}}' $wikiURL`);


	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"PCSI Identity Page\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}' $wikiURL";

	open (OLD, ">updateWiki-identityPage.oldPage") or die "Couldn't open updateWiki-identityPage.oldPage\n";
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



