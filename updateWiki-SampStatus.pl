#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Time::Local;

my $sampTable = "./samples_table.tsv";
my $runsTable = "./runs_table.tsv";

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content/96144312";
my $wikiID = 96144312;

my $l;
my @f;
my @headers;
my %row;

my $currentTime = time;

my $lib;
my %leaf;
my %gid;

my %lines;
my $line;

# read samp table
open (FILE, $sampTable) or die "Couldn't open $sampTable\n";

while ($l = <FILE>)
{
	if ($l =~ /^donor\texternal/)
	{
		@headers = split(/\t/, $l);
	}
	else
	{
		%row = ();
		@f = split(/\t/, $l);
		for (my $i = 0; $i < scalar(@f); $i++)
		{
			$row{$headers[$i]} = $f[$i];
		}

		%leaf = ();

		for my $h (qw/donor external sample seq_type library group_id sequencing/)
		{
			if ((exists $row{$h}) and (defined $row{$h}))
			{
				$leaf{$h} = $row{$h};
			}
			else
			{
				$leaf{$h} = "";
			}
		}

		$leaf{external} =~ s/,/ /g;

		if ($leaf{sample} =~ /^(.*?_.*?_.*?_.*?)_/)
		{
			$leaf{sample} = $1;
		}

		if ($leaf{seq_type} eq "gDNA")
		{
			$leaf{seq_type} = "DNA";
		}
		elsif ($leaf{seq_type} eq "whole RNA")
		{
			$leaf{seq_type} = "RNA";
		}

		if ($leaf{library} =~ /^(.*?_.*?_.*?_.*?)_(.*?_.*?_.*?)$/)
		{
			$leaf{library} = $2;
		}


		%gid = ();
		for my $g (split/,/, $leaf{group_id})
		{
			$gid{$g}++;
		}
		$leaf{group_id} = "";
		for my $g (keys %gid)
		{
			$leaf{group_id} .= "$g "
		}
		$leaf{group_id} =~ s/ $//;


		$leaf{sequencing} =~ s/;/; /g;


		if ($leaf{seq_type} eq "DNA")
		{
			$leaf{seq_type} = "<td class=\\\"highlight-blue\\\" data-highlight-colour=\\\"blue\\\">$leaf{seq_type}</td>";
		}
		elsif ($leaf{seq_type} eq "RNA")
		{
			$leaf{seq_type} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$leaf{seq_type}</td>";
		}
		else
		{
			$leaf{seq_type} = "<td>$leaf{seq_type}</td>";
		}

		if ($leaf{sequencing} =~ /\(R\)/)
		{
			$leaf{sequencing} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$leaf{sequencing}</td>";
		}
		elsif ($leaf{sequencing} =~ /\(F\)/)
		{
			$leaf{sequencing} = "<td class=\\\"highlight-red\\\" data-highlight-colour=\\\"red\\\">$leaf{sequencing}</td>";
		}
		else
		{
			$leaf{sequencing} = "<td>$leaf{sequencing}</td>";
		}


		for my $h (qw/donor external sample library group_id/)
		{
			$leaf{$h} = "<td>$leaf{$h}</td>";
		}

		$line = "";
		if ($leaf{donor} =~ /^<td>PCSI/)
		{
			for my $h (qw/donor external sample seq_type library group_id sequencing/)
			{
				$line .= "$leaf{$h}\t";
			}
		}

		$line =~ s/\t$//;
		$lines{$line}++;


	}
}


for my $l (reverse sort keys %lines)
{
	print "$l\n";
}






my %json;
my %summaryData;
my $prettyJson;




# push to wiki

my $page;
my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

open (OLD, "updateWiki-sampStatus.oldPage") or die "Couldn't open updateWiki-sampStatus.oldPage\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;

$page .= "<h2>Sample Status</h2>";

$page .= "<table><tbody>";
$page .= "<tr><th style=\\\"text-align: center;\\\">PCSI ID</th>
<th style=\\\"text-align: center;\\\">External ID</th>
<th style=\\\"text-align: center;\\\">Sample</th>
<th style=\\\"text-align: center;\\\">Type</th>
<th style=\\\"text-align: center;\\\">Library</th>
<th style=\\\"text-align: center;\\\">Group ID</th>
<th style=\\\"text-align: center;\\\">Sequencing Status</th></tr>";


for my $l (reverse sort keys %lines)
{
	$page .= "<tr>";
	for my $v (split (/\t/, $l))
	{
		$page .= "$v";
	}
	$page .= "</tr>";
}


$page .= "</tbody></table>";

open (CURLFILE, ">fileToCurl.txt") or die "Couldn't open >fileToCurl.txt\n";
print CURLFILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"Sample Status\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}";
close CURLFILE;

unless ($page eq $oldPage)
{
#	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{"id":"$wikiID","type":"page","title":"COMPASS Status","space":{"key":"PanCuRx"},"body":{"storage":{"value":"$page","representation":"storage"}}, "version":{"number":$pageVersion}}' $wikiURL`);
	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d @./fileToCurl.txt $wikiURL`);

#	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"COMPASS Status\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}' $wikiURL";
	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d @./fileToCurl.txt $wikiURL\n";

	open (OLD, ">updateWiki-sampStatus.oldPage") or die "Couldn't open updateWiki-sampStatus.oldPage\n";
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



