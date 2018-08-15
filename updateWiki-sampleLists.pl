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

my $prefix = "/.mounts/labs/PCSI/analysis/";
my @pages = qw/btc mcgill metachronous xmp resected pimo ramp eus sheba compass unicorns qcmg unassigned all/;

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content";
my %wikiIDs = (
	"resected" => 69049962,
	"pimo" => 69049984,
	"ramp" => 69049986,
	"eus" => 69049988,
	"sheba" => 69049990,
	"xmp" => 69049992,
	"compass" => 69049994,
	"unicorns" => 69050248,
	"unassigned" => 69049996,
	"qcmg" => 76092899,
	"all" => 69049998,
	"mcgill" => 87098307,
	"metachronous" => 87098304,
	"btc" => 87100688,
);


my %path = (
	"resected" => "resected",
	"pimo" => "pimo",
	"ramp" => "ramp",
	"eus" => "eus_matched",
	"sheba" => "sheba",
	"xmp" => "xmp",
	"compass" => "compass",
	"metachronous" => "metachronous",
	"mcgill" => "mcgill",
	"unicorns" => "unicorns",
	"qcmg" => "qcmg",
	"btc" => "btc",
	"unassigned" => "oicr",
	"all" => "oicr"
);


my %pageTitle = (
	"resected" => "Resected Sample List",
	"pimo" => "PIMO Sample List",
	"ramp" => "RAMP Sample List",
	"eus" => "EUS Sample List",
	"sheba" => "Sheba Sample List",
	"xmp" => "XMP Sample List",
	"compass" => "COMPASS Sample List",
	"unicorns" => "Unicorn Sample List",
	"qcmg" => "QCMG Sample List",
	"unassigned" => "Unassigned Sample List",
	"all" => "All Sample List",
	"metachronous" => "Metachronous Sample List",
	"mcgill" => "McGill Sample List",
	"btc" => "BTC Sample List",
);



my %assignedSamps;

for my $samples (@pages)
{
	createSampListPage($samples, "$prefix/$path{$samples}", "$wikiURL/$wikiIDs{$samples}", $wikiIDs{$samples}, $pageTitle{$samples}, \%assignedSamps);
}






sub createSampListPage
{
	my $sampType = shift;
	my $path = shift;
	my $wikiURL = shift;
	my $wikiID = shift;
	my $pageTitle = shift;
	my $assignedSamps = shift;

	my $outDir = "sampleLists";

	warn "Working on $path\n";

	my %data;

	my %row = ();



	my $summaryLS = `ls $path/*/*/wgs/bwa/0.6.2/results/*.summary.csv`;
	chomp $summaryLS;

	for my $summary (split(/\n/, $summaryLS))
	{
		parseSummary($summary, \%data);
		if ($sampType eq "unassigned")
		{
			unless (exists $assignedSamps->{"$data{tumour} $data{normal}"})
			{
	
				$data{result_date} = timeToYYMMDD( (stat($summary))[9] );
				$data{qc_status} = getQCstatus($summary);
	
				$data{ssm_count} = $data{snv_count} + $data{indel_count};
				doCellTweaks(\%data, $sampType);
	
	
				for my $type (qw/donor external_id tumour normal tumour_coverage normal_coverage mouse_content ssm_count sv_count cellularity ploidy qc_status result_date/)
				{
					$row{$summary}{$type} = $data{$type};
				}
			}
		}
		else
		{
			$assignedSamps->{"$data{tumour} $data{normal}"}++;

			$data{result_date} = timeToYYMMDD( (stat($summary))[9] );
			$data{qc_status} = getQCstatus($summary);

			$data{ssm_count} = $data{snv_count} + $data{indel_count};
			doCellTweaks(\%data, $sampType);


			for my $type (qw/donor external_id tumour normal tumour_coverage normal_coverage mouse_content ssm_count sv_count cellularity ploidy qc_status result_date/)
			{
				$row{$summary}{$type} = $data{$type};
			}

		}

	}

	
	my ($page, $l);
	my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
	my $pageVersion = $jsonPage->{version}{number};
	$pageVersion++;

	$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

	my $oldPageFile = "$outDir/$sampType.oldPage";
	open (OLD, $oldPageFile) or die "Couldn't open $oldPageFile\n";
	$l = <OLD>;
	chomp $l;
	my $oldPage = $l;
	close OLD;

	my @headers = qw/donor external_id tumour normal qc_status tumour_coverage normal_coverage mouse_content cellularity ssm_count sv_count ploidy result_date/;

	$page .= "<table><tbody>";
	$page .= "<tr>";

	for my $header (@headers)
	{
		$page .= "<th style=\\\"text-align: center;\\\">$header</th>";
	}
	$page .= "</tr>";

	for my $samp (sort keys %row)
	{
		$page .= "<tr>";
		for my $type (@headers)
		{
			$page .= "$row{$samp}{$type}";
		}
		$page .= "</tr>"
	}

	$page .= "</tbody></table>";


	unless ($page eq $oldPage)
	{
		open (FILE, ">$outDir/$sampType.curl") or die "Couldn't open >$outDir/$sampType.curl\n";
		print FILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"$pageTitle\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}\n";
		close FILE;
	
		$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d\@$outDir/$sampType.curl $wikiURL`);
	
		open (OLD, ">$oldPageFile") or die "Couldn't open $oldPageFile\n";
		print OLD "$page\n";
		close OLD;
	}
	else
	{
		print "skipping upload for $sampType: page did not change\n";
	}
	
}


sub parseSummary
{
	my $summary = shift;
	my $data = shift;

	my $l;
	my (@header, @f);
	%{ $data } = ();

	open (FILE, $summary) or die "Couldn't open $summary\n";
	while ($l = <FILE>)
	{
	    chomp $l;
	    if ($l =~ /^donor/)
	    {
	        @header = split(/,/, $l);
	    }
	    else
	    {
	        @f = split(/,/, $l);
	
	        for (my $i = 0; $i < scalar(@f); $i++)
	        {
	            $data->{$header[$i]} = $f[$i];
	        }
	    }
	}
	close FILE;
}

sub getQCstatus
{
	my $summary = shift;
	my $qcFile = "NA";

	my $qcStatus = "PASS";
	my ($l, $tool, $result, $message);

	if ($summary =~ /^(.*)\/(.*?)\/wgs\/bwa/)
	{
		$qcFile = "$1/$2/wgs/$2.qc.txt";
	}

	if ($qcFile eq "NA")
	{
		return "NA";
	}
	else
	{
		open (FILE, $qcFile) or die "Couldn't open $qcFile\n";

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
						if ($qcStatus eq "PASS")
						{
							$qcStatus = $result;
						}
					}
				}
				else
				{
					$qcStatus = $result;
				}
			}
		}
		close FILE;
	}
	return $qcStatus;

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


sub doCellTweaks
{
	my $data = shift;
	my $sampType = shift;

	if ($sampType eq "qcmg")
	{
		$data->{tumour} = "<td><a href=\\\"https://www.hpc.oicr.on.ca/archive/projects/PCSI/analysis/qcmg/$data->{donor}/$data->{tumour}/wgs/bwa/0.6.2/results/$data->{tumour}_landing.html\\\">$data->{tumour}</a></td>";
	}
	elsif ($sampType eq "btc")
	{
		$data->{tumour} = "<td><a href=\\\"https://www.hpc.oicr.on.ca/archive/projects/PCSI/analysis/btc/$data->{donor}/$data->{tumour}/wgs/bwa/0.6.2/results/$data->{tumour}_landing.html\\\">$data->{tumour}</a></td>";
	}
	else
	{
		$data->{tumour} = "<td><a href=\\\"https://www.hpc.oicr.on.ca/archive/projects/PCSI/analysis/oicr/$data->{donor}/$data->{tumour}/wgs/bwa/0.6.2/results/$data->{tumour}_landing.html\\\">$data->{tumour}</a></td>";
	}

	for my $type (qw/donor external_id normal ssm_count sv_count ploidy result_date/)
	{
		$data->{$type} = "<td>$data->{$type}</td>";
	}

	if ($data->{mouse_content} eq "NA")
	{
		$data->{mouse_content} = "<td>NA</td>";
	}
	else
	{
		$data->{mouse_content} = sprintf("%0.2f%%", $data->{mouse_content});
		$data->{mouse_content} = "<td>$data->{mouse_content}</td>";
	}

	if ($data->{tumour_coverage} eq "NA")
	{
		$data->{tumour_coverage} = "<td>NA</td>"
	}
	else
	{
		if ($data->{tumour_coverage} >= 45)
		{
			$data->{tumour_coverage} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data->{tumour_coverage}</td>"
		}
		elsif ($data->{tumour_coverage} >= 28)
		{
			$data->{tumour_coverage} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$data->{tumour_coverage}</td>"
		}
		else
		{
			$data->{tumour_coverage} = "<td class=\\\"highlight-red\\\" data-highlight-colour=\\\"red\\\">$data->{tumour_coverage}</td>"
		}
	}

	if ($data->{normal_coverage} eq "NA")
	{
		$data->{normal_coverage} = "<td>NA</td>"
	}
	else
	{
		if ($data->{normal_coverage} >= 30)
		{
			$data->{normal_coverage} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data->{normal_coverage}</td>"
		}
		elsif ($data->{normal_coverage} >= 28)
		{
			$data->{normal_coverage} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$data->{normal_coverage}</td>"
		}
		else
		{
			$data->{normal_coverage} = "<td class=\\\"highlight-red\\\" data-highlight-colour=\\\"red\\\">$data->{normal_coverage}</td>"
		}
	}

	if ($data->{cellularity} eq "NA")
	{
		$data->{cellularity} = "<td>NA</td>"
	}
	else
	{
		if ($data->{cellularity} >= 0.4)
		{
			$data->{cellularity} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data->{cellularity}</td>"
		}
		elsif ($data->{cellularity} >= 0.2)
		{
			$data->{cellularity} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$data->{cellularity}</td>"
		}
		else
		{
			$data->{cellularity} = "<td class=\\\"highlight-red\\\" data-highlight-colour=\\\"red\\\">$data->{cellularity}</td>"
		}
	}

	if ($data->{qc_status} eq "NA")
	{
		$data->{qc_status} = "<td>NA</td>"
	}
	else
	{
		if ($data->{qc_status} eq "PASS")
		{
			$data->{qc_status} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data->{qc_status}</td>"
		}
		elsif ($data->{qc_status} eq "WARN")
		{
			$data->{qc_status} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$data->{qc_status}</td>"
		}
		else
		{
			$data->{qc_status} = "<td class=\\\"highlight-red\\\" data-highlight-colour=\\\"red\\\">$data->{qc_status}</td>"
		}
	}

}



