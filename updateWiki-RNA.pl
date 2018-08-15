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
my $rna_ls = "$prefix/RNAseq/*/*/rna/star/2.5.2a/collapsed/Log.final.out";

my $outDir = "rna";

my $sampTable = "/u/rdenroche/samples_table.tsv";

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content";
my $wikiID = 99355663;
my $pageTitle = "RNA Metrics";

my $uniqCut = 30000000;

my %skipDonor = (
	"old" => 1,
	"ASHPC" => 1,
	"MPCC" => 1,
);


#                                 Started job on |       Mar 27 10:14:32
#                             Started mapping on |       Mar 27 10:55:30
#                                    Finished on |       Mar 27 12:43:18
#       Mapping speed, Million of reads per hour |       37.26
#
#                          Number of input reads |       66947844
#                      Average input read length |       202
#                                    UNIQUE READS:
#                   Uniquely mapped reads number |       60228797
#                        Uniquely mapped reads % |       89.96%
#                          Average mapped length |       201.45
#                       Number of splices: Total |       67544032
#            Number of splices: Annotated (sjdb) |       67506571
#                       Number of splices: GT/AG |       66848398
#                       Number of splices: GC/AG |       572422
#                       Number of splices: AT/AC |       68892
#               Number of splices: Non-canonical |       54320
#                      Mismatch rate per base, % |       0.18%
#                         Deletion rate per base |       0.01%
#                        Deletion average length |       1.54
#                        Insertion rate per base |       0.00%
#                       Insertion average length |       1.27
#                             MULTI-MAPPING READS:
#        Number of reads mapped to multiple loci |       5744484
#             % of reads mapped to multiple loci |       8.58%
#        Number of reads mapped to too many loci |       243982
#             % of reads mapped to too many loci |       0.36%
#                                  UNMAPPED READS:
#       % of reads unmapped: too many mismatches |       0.00%
#                 % of reads unmapped: too short |       0.51%
#                     % of reads unmapped: other |       0.58%
#                                  CHIMERIC READS:
#                       Number of chimeric reads |       122286
#                            % of chimeric reads |       0.18%
#rdenroche@pancure-report:~$ ls /.mounts/labs/PCSI/analysis/RNAseq/*/*/rna/star/2.5.2a/collapsed/Log.final.out


my %data;
my $samp;
my $l;

my %external;
my (@h, @f);
my %row;

open (FILE, $sampTable) or die "Couldn't open $sampTable\n";

while ($l = <FILE>)
{
	chomp $l;
	if ($l =~ /^donor/)
	{
		@h = split(/\t/, $l);
	}
	else
	{
		@f = split(/\t/, $l);
		%row = ();
		for (my $i = 0; $i < scalar(@f); $i++)
		{
			$row{$h[$i]} = $f[$i];
			print "here\n";
		}

		$row{donor} =~ s/_//;
		$external{$row{donor}} = $row{external};

		print "$row{donor} => $row{external}\n";
	}
}

close FILE;




my $ls = `ls $rna_ls`;
chomp $ls;

for my $logFile (split(/\n/, $ls))
{
	if ($logFile =~ /RNAseq\/(.*?)\/(.*?)\/rna/)
	{
		$samp = $2;
		$data{$samp}{donor} = $1;
		$data{$samp}{sample} = $samp;
	}
	else
	{
		die "Couldn't find donor/sample in $logFile\n";
	}

	$data{$samp}{analysis_time} = timeToYYMMDD( (stat($logFile))[9] );

	if (exists $external{$data{$samp}{donor}})
	{
		$data{$samp}{external} = $external{$data{$samp}{donor}};
	}

	open (FILE, $logFile) or die "Couldn't open $logFile\n";
	while ($l = <FILE>)
	{
		chomp $l;
		if ($l =~ /Number of input reads \|\t(.*)/)
		{
			$data{$samp}{input_reads} = $1;
		}
		elsif ($l =~ /Uniquely mapped reads number \|\t(.*)/)
		{
			$data{$samp}{uniquely_mapped_reads} = $1;
		}
		elsif ($l =~ /Uniquely mapped reads % \|\t(.*)/)
		{
			$data{$samp}{uniquely_mapped_rate} = $1;
		}
		elsif ($l =~ /Number of reads mapped to multiple loci \|\t(.*)/)
		{
			$data{$samp}{multiply_mapped_reads} = $1;
		}
	}
	close FILE;
}




for my $i (qw/donor sample external input_reads uniquely_mapped_reads uniquely_mapped_rate multiply_mapped_reads analysis_time/)
{
	print "$i\t";
}
print "\n";
for my $s (sort keys %data)
{
	for my $i (qw/donor sample external input_reads uniquely_mapped_reads uniquely_mapped_rate multiply_mapped_reads analysis_time/)
	{
		if (exists $data{$s}{$i})
		{
			print "$data{$s}{$i}\t";
		}
		else
		{
			print "\t";
		}
	}
	print "\n";
}







my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL/$wikiID`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL/$wikiID?expand=body.storage`);		# get current page body so we can check if an update is necessary

my $oldPageFile = "$outDir/rna.oldPage";
open (OLD, $oldPageFile) or die "Couldn't open $oldPageFile\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;


my $page = "";
my @headers = qw/donor sample external input_reads uniquely_mapped_reads uniquely_mapped_rate multiply_mapped_reads analysis_time/;


# add tags
#<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data->{tumour_coverage}</td>

for my $samp (sort keys %data)
{
	for my $type (qw/donor sample external input_reads uniquely_mapped_rate multiply_mapped_reads analysis_time/)
	{
		if (exists $data{$samp}{$type})
		{
			$data{$samp}{$type} = "<td>$data{$samp}{$type}</td>";
		}
		else
		{
			$data{$samp}{$type} = "<td></td>";
		}
	}

	if ($data{$samp}{uniquely_mapped_reads} >= $uniqCut)
	{
		$data{$samp}{uniquely_mapped_reads} = "<td class=\\\"highlight-green\\\" data-highlight-colour=\\\"green\\\">$data{$samp}{uniquely_mapped_reads}</td>";
	}
	else
	{
		$data{$samp}{uniquely_mapped_reads} = "<td class=\\\"highlight-yellow\\\" data-highlight-colour=\\\"yellow\\\">$data{$samp}{uniquely_mapped_reads}</td>";
	}
}

for my $d (keys %skipDonor)
{
	$skipDonor{"<td>$d</td>"}++;
}



$page .= "<table><tbody>";
$page .= "<tr>";

for my $header (@headers)
{
	$page .= "<th style=\\\"text-align: center;\\\">$header</th>";
}
$page .= "</tr>";

for my $samp (sort keys %data)
{
	unless (exists $skipDonor{$data{$samp}{donor}})
	{
		$page .= "<tr>";
		for my $type (@headers)
		{
			$page .= "$data{$samp}{$type}";
		}
		$page .= "</tr>";
	}
}

$page .= "</tbody></table>";


unless ($page eq $oldPage)
{
	open (FILE, ">$outDir/rna.curl") or die "Couldn't open >$outDir/rna.curl\n";
	print FILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"$pageTitle\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}\n";
	close FILE;

	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d\@$outDir/rna.curl $wikiURL/$wikiID`);

	open (OLD, ">$oldPageFile") or die "Couldn't open $oldPageFile\n";
	print OLD "$page\n";
	close OLD;
}
else
{
	print "skipping upload - page did not change\n";
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

