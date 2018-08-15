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
my $limsUrl = "https://pinery.hpc.oicr.on.ca:8443/pinery/";

my $wikiURL = "https://wiki.oicr.on.ca/rest/api/content/66301615";
my $wikiID = 66301615;

my $l;
my @f;

my $comp;

my $daysToReport = 8 * 7;		# 8 weeks;

my $biopsiedFile = "/u/rdenroche/COMPASS_Biopsy_Times.txt";
my $reportedFile = "/u/rdenroche/COMPASS_DNA_Reported.txt";
my $currentTime = time;
my %biopsied;
my %reportedDNA;

open (FILE, $biopsiedFile) or die "Couldn't open $biopsiedFile\n";

my ($mon,$day,$year);

while ($l = <FILE>)
{
	chomp $l;
	@f = split(/\t/, $l);

	($day,$mon,$year) = split(/\//, $f[1]);
	$mon--;
	$biopsied{$f[0]} = timelocal(0,0,0,$day,$mon,$year);
}
close FILE;


open (FILE, $reportedFile) or die "Couldn't open $reportedFile\n";

while ($l = <FILE>)
{
	chomp $l;
	@f = split(/\t/, $l);

	($day,$mon,$year) = split(/\//, $f[1]);
	$mon--;
	$reportedDNA{$f[0]} = timelocal(0,0,0,$day,$mon,$year);
}
close FILE;







my %json;
my %summaryData;
my $prettyJson;


# read table with existing info, including "done" status to cut down on lims queries
my %done = (
	"PCSIT_0001" => 1
);



my %lanes;
my %runs;
my $url;
my ($run_ls);

warn "\n Starting run hierarchy download\n";
my ($barcode,$lane,$startDate);
my $runsRef;
if ($doTest == 0)
{
#	$prettyJson = `curl -X GET http://pinery.gsi.oicr.on.ca:8080/pinery-ws-miso/sequencerruns`;
	$prettyJson = `curl -X GET http://pinery-prod.hpc.oicr.on.ca:8080/pinery-ws-miso/sequencerruns`;
	$prettyJson =~ s/\n//g;
	
	$runsRef = decode_json($prettyJson);
}
else
{
	open (JSON, "sequencerruns_160229.json") or die "Couldn't open sequencerruns_160229.json\n";
	$runsRef = decode_json(<JSON>);
	close JSON;
}
warn " Finished run hierarchy download\n\n";

warn "  Parsing run hierarchy\n";
for (my $i = 0; $i < scalar(@$runsRef); $i++)
{
	unless($runsRef->[$i]{state} eq "Failed")
	{
		$runs{$runsRef->[$i]{url}}{name} = $runsRef->[$i]{name};
		$runs{$runsRef->[$i]{url}}{barcode} = $runsRef->[$i]{barcode};
		$runs{$runsRef->[$i]{url}}{date} = $runsRef->[$i]{created_date};

		for (my $j = 0; $j <= $#{ $runsRef->[$i]{positions} }; $j++)
		{
			for (my $k = 0; $k <= $#{ $runsRef->[$i]{positions}[$j]{samples} }; $k++)
			{
				$url = $runsRef->[$i]{positions}[$j]{samples}[$k]{url};
				if (exists $lanes{$url}{$runsRef->[$i]{url}})
				{
					$lanes{$url}{$runsRef->[$i]{url}} .= "," . $runsRef->[$i]{positions}[$j]{position};
				}
				else
				{
					$lanes{$url}{$runsRef->[$i]{url}} = $runsRef->[$i]{positions}[$j]{position};
				}
			}
		}
	}
}

%json = ();		# frees ram, ideally


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
my %leaves;

my ($tisURL,$tisName,$tisType,$tisCreate,$extURL,$extName,$extType,$extCreate,$alqURL,$alqName,$alqType,$alqCreate,$libURL,$libName,$libType,$libCreate,$seqURL,$seqName,$seqType,$seqCreate);
my ($capURL,$capName,$capType,$capCreate);

warn " Converting sample hierarchy into json\n";
for (my $i = 0; $i < scalar(@$samplesRef); $i++)
{
	$json{$samplesRef->[$i]{url}} = $samplesRef->[$i];
}

$samplesRef = "";		# free some ram, ideally

my ($name,$externalName,$isCompass);

warn " Parsing sample hierarchy\n";
for my $url (keys %json)
{
	if ($json{$url}{sample_type} eq "Identity")
	{
		$isCompass = 0;
		$name = $json{$url}{name};
		if (exists $json{$url}{attributes})
		{
			for (my $j = 0; $j <= $#{ $json{$url}{attributes} }; $j++)
			{
				if ($json{$url}{attributes}[$j]{name} eq "Sub-project")
				{
					if ($json{$url}{attributes}[$j]{value} eq "COMPASS")
				{
						$isCompass = 1;
					}
				}
				elsif ($json{$url}{attributes}[$j]{name} eq "External Name")
				{
					$externalName = $json{$url}{attributes}[$j]{value};
					$externalName =~ s/,/ /g;
					if (($externalName =~ /COMP/) and ($name =~ /^PCSI/))
					{
						$isCompass = 1;
					}
				}
			}
	
			if ($isCompass == 1)
			{
				$name = $json{$url}{name};
				unless (exists $done{$name})
				{
					$data{$name}{date} = $json{$url}{created_date};
					$data{$name}{external_name} = $externalName;
					$data{$name}{url} = $url;

					$comp = $externalName;
					$comp =~ s/.*COMP/COMP/;
#					$comp =~ s/-/_/;
					$comp =~ s/ .*//;



					unless (exists $biopsied{$comp})
					{
						$biopsied{$comp} = -1;
					}
	
					$summaryData{$comp}{pcsi} = $name;
					$summaryData{$comp}{received} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";

					if (exists $json{$url}{children})
					{
						for (my $tisIter = 0; $tisIter <= $#{ $json{$url}{children} }; $tisIter++)
						{
							$tisURL = $json{$url}{children}[$tisIter]{url};
				
							$tisName = $json{$tisURL}{name};
							$tisType = $json{$tisURL}{sample_type};
							$tisCreate = $json{$tisURL}{created_date};

							$data{$name}{tissue}{$tisName}{type} = $tisType;
							$data{$name}{tissue}{$tisName}{date} = $tisCreate;
							$data{$name}{tissue}{$tisName}{url} = $tisURL;
							$data{$name}{tissue}{$tisName}{parent} = $name;
	
							if (exists $json{$tisURL}{children})
							{
								for (my $extIter = 0; $extIter <= $#{ $json{$tisURL}{children} }; $extIter++)
								{
									$extURL = $json{$tisURL}{children}[$extIter]{url};
		
									$extName = $json{$extURL}{name};
									$extType = $json{$extURL}{sample_type};
									$extCreate = $json{$extURL}{created_date};
		
									$data{$name}{extraction}{$extName}{type} = $extType;
									$data{$name}{extraction}{$extName}{date} = $extCreate;
									$data{$name}{extraction}{$extName}{url} = $extURL;
									$data{$name}{extraction}{$extName}{parent} = "tissue,$tisName";


									if ($extType eq "whole RNA")		# need to handle the capture step
									{
										$summaryData{$comp}{extracted_rna}++;
										
										if (exists $json{$extURL}{children})
										{
											for (my $alqIter = 0; $alqIter <= $#{ $json{$extURL}{children} }; $alqIter++)
											{
												$alqURL = $json{$extURL}{children}[$alqIter]{url};

												$alqName = $json{$alqURL}{name};
												$alqType = $json{$alqURL}{sample_type};
												$alqCreate = $json{$alqURL}{created_date};

												for (my $i = 0; $i <= $#{ $json{$alqURL}{attributes} }; $i++)
												{
													if ($json{$alqURL}{attributes}[$i]{name} eq "Purpose")
													{
														$data{$name}{aliquot}{$alqName}{purpose} = $json{$alqURL}{attributes}[$i]{value};
													}
												}

												$data{$name}{aliquot}{$alqName}{type} = $alqType;
												$data{$name}{aliquot}{$alqName}{date} = $alqCreate;
												$data{$name}{aliquot}{$alqName}{url} = $alqURL;
												$data{$name}{aliquot}{$alqName}{parent} = "extraction,$extName";

												if (exists $json{$alqURL}{children})
												{
													for (my $capIter = 0; $capIter <= $#{ $json{$alqURL}{children} }; $capIter++)
													{
														$capURL = $json{$alqURL}{children}[$capIter]{url};

														$capName = $json{$capURL}{name};
														$capType = $json{$capURL}{sample_type};
														$capCreate = $json{$capURL}{created_date};

														$data{$name}{capture}{$capName}{type} = $capType;
														$data{$name}{capture}{$capName}{date} = $capCreate;
														$data{$name}{capture}{$capName}{url} = $capURL;
														$data{$name}{capture}{$capName}{parent} = "aliquot,$alqName";

														if (exists $json{$capURL}{children})
														{
															for (my $libIter = 0; $libIter <= $#{ $json{$capURL}{children} }; $libIter++)
															{
																$libURL = $json{$capURL}{children}[$libIter]{url};
		
																$libName = $json{$libURL}{name};
																$libType = $json{$libURL}{sample_type};
																$libCreate = $json{$libURL}{created_date};
		
																$data{$name}{library}{$libName}{type} = $libType;
																$data{$name}{library}{$libName}{date} = $libCreate;
																$data{$name}{library}{$libName}{url} = $libURL;
																$data{$name}{library}{$libName}{parent} = "capture,$capName";
		
																$summaryData{$comp}{libs_rna}++;
		
																if (exists $json{$libURL}{children})
																{
																	for (my $seqIter = 0; $seqIter <= $#{ $json{$libURL}{children} }; $seqIter++)
																	{
																		$seqURL = $json{$libURL}{children}[$seqIter]{url};
																		$seqName = $json{$seqURL}{name};
																		$seqType = $json{$seqURL}{sample_type};
																		$seqCreate = $json{$seqURL}{created_date};
																		
																		$data{$name}{library_seq}{$seqName}{type} = $seqType;
																		$data{$name}{library_seq}{$seqName}{date} = $seqCreate;
																		$data{$name}{library_seq}{$seqName}{url} = $seqURL;
																		$data{$name}{library_seq}{$seqName}{parent} = "library,$libName";
			
																		push(@{ $leaves{$name} }, "a,library_seq,$seqName");
				
																		if (exists $lanes{$seqURL})
																		{
																			for my $run (keys %{ $lanes{$seqURL} })
																			{
																				for my $pos (split (/,/, $lanes{$seqURL}{$run}))
																				{
																					$summaryData{$comp}{seq_start_rna}++;
	
																					$run_ls = `ls /.mounts/labs/prod/archive/*/$runs{$run}{name}/oicr_run_complete`;
																					chomp $run_ls;
																					if (-e $run_ls)
																					{
																						$summaryData{$comp}{seq_end_rna}++;
																					}
																				}
																			}
																		}
																	}
																}
																else
																{
																	push(@{ $leaves{$name} }, "b,library,$libName");
																}
															}
														}
														else
														{
															push (@{ $leaves{$name} }, "c,capture,$libName");
														}
													}
												}
												else
												{
													push(@{ $leaves{$name} }, "d,aliquot,$alqName");
												}
											}
										}
										else
										{
											push(@{ $leaves{$name} }, "e,extraction,$extName");
										}
									}
									else
									{
										$summaryData{$comp}{extracted_dna}++;

										if (exists $json{$extURL}{children})
										{
											for (my $alqIter = 0; $alqIter <= $#{ $json{$extURL}{children} }; $alqIter++)
											{
												$alqURL = $json{$extURL}{children}[$alqIter]{url};
					
												$alqName = $json{$alqURL}{name};
												$alqType = $json{$alqURL}{sample_type};
												$alqCreate = $json{$alqURL}{created_date};
	
												for (my $i = 0; $i <= $#{ $json{$alqURL}{attributes} }; $i++)
												{
													if ($json{$alqURL}{attributes}[$i]{name} eq "Purpose")
													{
														$data{$name}{aliquot}{$alqName}{purpose} = $json{$alqURL}{attributes}[$i]{value};
													}
												}
				
												$data{$name}{aliquot}{$alqName}{type} = $alqType;
												$data{$name}{aliquot}{$alqName}{date} = $alqCreate;
												$data{$name}{aliquot}{$alqName}{url} = $alqURL;
												$data{$name}{aliquot}{$alqName}{parent} = "extraction,$extName";
		
												if (exists $json{$alqURL}{children})
												{
													for (my $libIter = 0; $libIter <= $#{ $json{$alqURL}{children} }; $libIter++)
													{
														$libURL = $json{$alqURL}{children}[$libIter]{url};
							
														$libName = $json{$libURL}{name};
														$libType = $json{$libURL}{sample_type};
														$libCreate = $json{$libURL}{created_date};
	
														$data{$name}{library}{$libName}{type} = $libType;
														$data{$name}{library}{$libName}{date} = $libCreate;
														$data{$name}{library}{$libName}{url} = $libURL;
														$data{$name}{library}{$libName}{parent} = "aliquot,$alqName";
		
														$summaryData{$comp}{libs_dna}++;

														if (exists $json{$libURL}{children})
														{
															for (my $seqIter = 0; $seqIter <= $#{ $json{$libURL}{children} }; $seqIter++)
															{
																$seqURL = $json{$libURL}{children}[$seqIter]{url};

																print "$seqURL\n";
									
																$seqName = $json{$seqURL}{name};
																$seqType = $json{$seqURL}{sample_type};
																$seqCreate = $json{$seqURL}{created_date};
													
																$data{$name}{library_seq}{$seqName}{type} = $seqType;
																$data{$name}{library_seq}{$seqName}{date} = $seqCreate;
																$data{$name}{library_seq}{$seqName}{url} = $seqURL;
																$data{$name}{library_seq}{$seqName}{parent} = "library,$libName";
	
																push(@{ $leaves{$name} }, "a,library_seq,$seqName");
		
																if (exists $lanes{$seqURL})
																{
																	for my $run (keys %{ $lanes{$seqURL} })
																	{
																		for my $pos (split(/,/, $lanes{$seqURL}{$run}))
																		{
																			$summaryData{$comp}{seq_start_dna}++;

																			$run_ls = `ls /.mounts/labs/prod/archive/*/$runs{$run}{name}/oicr_run_complete`;
																			chomp $run_ls;
																			if (-e $run_ls)
																			{
																				$summaryData{$comp}{seq_end_dna}++;
																			}
																		}
																	}
																}
															}
														}
														else
														{
															push(@{ $leaves{$name} }, "b,library,$libName");
														}
													}
												}
												else
												{
													push(@{ $leaves{$name} }, "c,aliquot,$alqName");
												}
											}
										}
										else
										{
											push(@{ $leaves{$name} }, "d,extraction,$extName");
										}
									}
								}
							}
							else
							{
								push(@{ $leaves{$name} }, "e,tissue,$tisName");
							}
						}
					}
				}
			}
		}
	}
}
%json = ();		# frees ram, ideally


my $row;

warn "  Printing table\n";
# print table
my ($donor,$external,$samp,$rec_date,$ext_date,$lib_date,$seq_start,$run_name,$seq_complete,$aligned_date,$analyzed_date,$report_date);		# $lane after $run_name (already declared)
print "Donor,External Id,Sample,Tissue Type,Received Date,Extracted Date,Library Created Date,Sequencing Start,Sequencing Run,Sequencing Lane,Sequencing Complete,Aligned Date,Analyzed Date,Reported Date\n";
for $name (sort keys %data)
{
	if (exists $leaves{$name})
	{
		for my $leaf (sort @{ $leaves{$name} })
		{
			$row = processLeaf($leaf, $name, \%data, \%lanes, \%runs);
			unless ($row eq "")
			{
				($donor,$external,$samp,$tisType,$rec_date,$ext_date,$lib_date,$seq_start,$run_name,$lane,$seq_complete,$aligned_date,$analyzed_date,$report_date) = split(/,/, $row);
				print "$donor,$external,$samp,$tisType,$rec_date,$ext_date,$lib_date,$seq_start,$run_name,$lane,$seq_complete,$aligned_date,$analyzed_date,$report_date\n";
			}
		}
	}
}


# go hunting for results

my $tumour;
my $normal;
my $ls;
my $pcsiDir = "/.mounts/labs/PCSI/analysis/compass";
my $alignerPath = "wgs/bwa/0.6.2/";
my $no_Donor;

my %jsonHash;
my $coverage;

for $comp (sort keys %summaryData)
{
	$donor = $summaryData{$comp}{pcsi};

	$normal = "$donor*_R";
	$tumour = "$donor*_[MP]";


	$no_Donor = $donor;
	$no_Donor =~ s/_//;

	$ls = `ls $pcsiDir/$no_Donor/$normal*/$alignerPath/json/*.json | grep -v PE`;		# this is gross...
	chomp $ls;
	$ls =~ s/\n.*$//;		# also gross

	if ($ls ne "")
	{
		open(JSON, $ls) or die "Couldn't open $ls\n";
		if ($l = <JSON>)
		{
			$jsonHash{j} = decode_json($l);
			if (($jsonHash{j}{"target size"} > 0) and ($jsonHash{j}{"mapped reads"}))
			{
				$coverage = ($jsonHash{j}{"aligned bases"} * ($jsonHash{j}{"reads on target"} / $jsonHash{j}{"mapped reads"}) ) / $jsonHash{j}{"target size"};
			}
			else
			{
				$coverage = "NA";
			}
			$summaryData{$comp}{norm_cov} =  sprintf("%0.1f", $coverage);
		}
	}


	$ls = `ls $pcsiDir/$no_Donor/$tumour*/$alignerPath/json/*.json | grep -v PE`;		# this is gross...
	chomp $ls;

	$ls = (split(/\n/, $ls))[0];

	if ($ls ne "")
	{
		open(JSON, $ls) or die "Couldn't open $ls\n";
		if ($l = <JSON>)
		{
			$jsonHash{j} = decode_json($l);
			$coverage = 0;
			if (($jsonHash{j}{"target size"} > 0) and ($jsonHash{j}{"mapped reads"} > 0))
			{
				$coverage = ($jsonHash{j}{"aligned bases"} * ($jsonHash{j}{"reads on target"} / $jsonHash{j}{"mapped reads"}) ) / $jsonHash{j}{"target size"};
			}
			$summaryData{$comp}{tum_cov} =  sprintf("%0.1f", $coverage);
		}
	}

	$ls = `ls $pcsiDir/$no_Donor/$tumour*/$alignerPath/final_strelka-mutect/*final.vcf`;
	chomp $ls;
	$ls =~ s/\n.*$//;		# also gross

	if (-e $ls)
	{
		if ((stat($ls))[7] > 0)
		{
			$summaryData{$comp}{ssm} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}

	$ls = `ls $pcsiDir/$no_Donor/$tumour*/$alignerPath/final_gatk-germline/*.germline.final.vcf`;
	chomp $ls;
	$ls =~ s/\n.*$//;		# also gross

	if (-e $ls)
	{
		if ((stat($ls))[7] > 0)
		{
			$summaryData{$comp}{sgv} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}

	$ls = `ls $pcsiDir/$no_Donor/$tumour*/$alignerPath/HMMcopy/0.1.1/*.cnv_somatic_segments`;
	chomp $ls;
	$ls =~ s/\n.*$//;		# also gross

	if (-e $ls)
	{
		if ((stat($ls))[7] > 0)
		{
			$summaryData{$comp}{cna} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}

	$ls = `ls $pcsiDir/$no_Donor/$tumour*/$alignerPath/final_crest-delly/*.annotatedSV.tsv`;
	chomp $ls;
	$ls =~ s/\n.*$//;		# also gross

	if (-e $ls)
	{
		if ((stat($ls))[7] > 0)
		{
			$summaryData{$comp}{sv} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}
}






# push to wiki

my $page;
my $jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL`);		# get current page version so we can POST with version++
my $pageVersion = $jsonPage->{version}{number};
$pageVersion++;

$jsonPage = decode_json(`curl -K ~/.curlpass -X GET $wikiURL?expand=body.storage`);		# get current page body so we can check if an update is necessary

open (OLD, "updateWiki-COMPASS.oldPage") or die "Couldn't open updateWiki-COMPASS.oldPage\n";
$l = <OLD>;
chomp $l;
my $oldPage = $l;
close OLD;

$page .= "<h2>DNA Summary</h2>";

$page .= "<table><tbody>";
$page .= "<tr><th style=\\\"text-align: center;\\\">PCSI ID</th><th style=\\\"text-align: center;\\\">Case</th><th style=\\\"text-align: center;\\\">Extracted</th><th style=\\\"text-align: center;\\\">Libraries</th><th style=\\\"text-align: center;\\\">Lanes<br/>Started</th><th style=\\\"text-align: center;\\\">Lanes<br/>Complete</th><th style=\\\"text-align: center;\\\">Normal<br/>Coverage</th><th style=\\\"text-align: center;\\\">Tumour<br/>Coverage</th><th style=\\\"text-align: center;\\\">SSM</th><th style=\\\"text-align: center;\\\">SGV</th><th style=\\\"text-align: center;\\\">CNA</th><th style=\\\"text-align: center;\\\">SV</th><th style=\\\"text-align: center;\\\">Reported</th><th style=\\\"text-align: center;\\\">Days Since<br/>Biopsy</th></tr>";

my %mins = (
	"libs_dna" => 3,
	"extracted_dna" => 2,
	"seq_start_dna" => 5,
	"norm_cov" => 30,
	"tum_cov" => 45,

	"libs_rna" => 1,
	"extracted_rna" => 1,
	"seq_start_rna" => 1,
	"uniq_reads" => 50000000,
);

my $pcsiID;

for $comp (sort keys %biopsied)
{

	$pcsiID = "";
	if (exists $summaryData{$comp}{pcsi})
	{
		$pcsiID = $summaryData{$comp}{pcsi};
	}

	$page .= "<tr><td>$pcsiID</td><td><strong>$comp</strong></td>";

	if (exists $summaryData{$comp}{seq_end_dna})
	{
		if (($summaryData{$comp}{seq_end_dna} >= $mins{seq_start_dna}) and ($summaryData{$comp}{seq_end_dna} >= $summaryData{$comp}{seq_start_dna}))
		{
			$summaryData{$comp}{seq_end_dna} .= " <ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}

	# need to handle RNA here before the seq stats have their checkmarks added
	if (exists $summaryData{$comp}{seq_end_rna})
	{
		if (($summaryData{$comp}{seq_end_rna} >= $mins{seq_start_rna}) and ($summaryData{$comp}{seq_end_rna} >= $summaryData{$comp}{seq_start_rna}))
		{
			$summaryData{$comp}{seq_end_rna} .= " <ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
		}
	}

	for my $head (keys %mins)
	{
		if (exists $summaryData{$comp}{$head})
		{
			if ($summaryData{$comp}{$head} >= $mins{$head})
			{
				$summaryData{$comp}{$head} .= " <ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
			}
		}
	}

	if ($biopsied{$comp} == -1)
	{
		$summaryData{$comp}{days_dna} = "";
	}
	else
	{
		if (exists $reportedDNA{$comp})
		{
			$summaryData{$comp}{report_dna} = "<ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
	
			$summaryData{$comp}{days_dna} = int((($reportedDNA{$comp} - $biopsied{$comp}) / (60*60*24)) + 0.5);
			if ($summaryData{$comp}{days_dna} <= $daysToReport)
			{
				$summaryData{$comp}{days_dna} .= " <ac:image><ri:attachment ri:filename=\\\"check.png\\\"/></ac:image>";
			}
			else
			{
				$summaryData{$comp}{days_dna} .= " <ac:image><ri:attachment ri:filename=\\\"error.png\\\"/></ac:image>";
			}
		}
		else
		{
			$summaryData{$comp}{days_dna} = int((($currentTime - $biopsied{$comp}) / (60*60*24)) + 0.5);
		}
	}

	for my $head (qw/extracted_dna libs_dna seq_start_dna seq_end_dna norm_cov tum_cov ssm sgv cna sv report_dna days_dna/)
	{
		if (exists $summaryData{$comp}{$head})
		{
			$page .= "<td style=\\\"text-align: center;\\\">$summaryData{$comp}{$head}</td>";
		}
		else
		{
			$page .= "<td></td>";
		}
	}
	$page .= "</tr>";
}
$page .= "</tbody></table>";

$page .= "<h2>RNA Summary</h2>";

$page .= "<table><tbody>";
$page .= "<tr><th style=\\\"text-align: center;\\\">PCSI ID</th><th style=\\\"text-align: center;\\\">Case</th><th style=\\\"text-align: center;\\\">Extracted</th><th style=\\\"text-align: center;\\\">Libraries</th><th style=\\\"text-align: center;\\\">Lanes<br/>Started</th><th style=\\\"text-align: center;\\\">Lanes<br/>Complete</th><th style=\\\"text-align: center;\\\">Unique<br/>Reads</th><th style=\\\"text-align: center;\\\">Expressions</th><th style=\\\"text-align: center;\\\">Isoforms</th><th style=\\\"text-align: center;\\\">Fusions</th><th style=\\\"text-align: center;\\\">Reported</th></tr>";

for $comp (sort keys %biopsied)
{
	$pcsiID = "";
	if (exists $summaryData{$comp}{pcsi})
	{
		$pcsiID = $summaryData{$comp}{pcsi};
	}

	$page .= "<tr><td>$pcsiID</td><td><strong>$comp</strong></td>";


	for my $head (qw/extracted_rna libs_rna seq_start_rna seq_end_rna uniq_reads expression isoforms fusions report_rna/)
	{
		if (exists $summaryData{$comp}{$head})
		{
			$page .= "<td style=\\\"text-align: center;\\\">$summaryData{$comp}{$head}</td>";
		}
		else
		{
			$page .= "<td></td>";
		}
	}
	$page .= "</tr>";
}
$page .= "</tbody></table>";

open (CURLFILE, ">fileToCurl.txt") or die "Couldn't open >fileToCurl.txt\n";
print CURLFILE "{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"COMPASS Status\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}";
close CURLFILE;

unless ($page eq $oldPage)
{
#	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{"id":"$wikiID","type":"page","title":"COMPASS Status","space":{"key":"PanCuRx"},"body":{"storage":{"value":"$page","representation":"storage"}}, "version":{"number":$pageVersion}}' $wikiURL`);
	$jsonPage = decode_json(`curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d @./fileToCurl.txt $wikiURL`);

#	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d'{\"id\":\"$wikiID\",\"type\":\"page\",\"title\":\"COMPASS Status\",\"space\":{\"key\":\"PanCuRx\"},\"body\":{\"storage\":{\"value\":\"$page\",\"representation\":\"storage\"}}, \"version\":{\"number\":$pageVersion}}' $wikiURL";
	print "curl -K ~/.curlpass -X PUT -H 'Content-Type: application/json' -d @./fileToCurl.txt $wikiURL";

	open (OLD, ">updateWiki-COMPASS.oldPage") or die "Couldn't open updateWiki-COMPASS.oldPage\n";
	print OLD "$page\n";
	close OLD;
}
else
{
	print "skipping upload: page did not change\n";
}



sub processLeaf
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;
	my $lanesRef = shift;
	my $runsRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	if ($type eq "library_seq")
	{
		return processLibSeq($leaf, $name, $dataRef, $lanesRef, $runsRef);
	}
	elsif ($type eq "library")
	{
		return processLibrary($leaf, $name, $dataRef) . ",,,,,,,";	# up to lib create date
	}
	elsif ($type eq "aliquot")
	{
		return processAliquot($leaf, $name, $dataRef) . ",,,,,,,,";	# up to extracted date
	}
	elsif ($type eq "extraction")
	{
		return processExtraction($leaf, $name, $dataRef) . ",,,,,,,,";	# up to extracted date
	}
	elsif ($type eq "tissue")
	{
		return processTissue($leaf, $name, $dataRef) . ",,,,,,,,,";	# up to received date
	}
}


sub processLibSeq
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;
	my $lanesRef = shift;
	my $runsRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	my $seq_start = "";
	my $run_name = "";
	my $lane = "";
	my $seq_complete = "";
	my $aligned_date = "";
	my $analyzed_date = "";
	my $report_date = "";

	my $seqURL = $dataRef->{$name}{library_seq}{$leafName}{url};
	my $parent = $dataRef->{$name}{library_seq}{$leafName}{parent};

	my ($runName,$runDate,$runBarcode);
	my $run_ls;

	if (exists $lanesRef->{$seqURL})
	{
		for my $runURL (sort { $runs{$a}{name} cmp $runs{$b}{name} } keys %{ $lanesRef->{$seqURL} })
		{
			$run_name = $runsRef->{$runURL}{name};
			$seq_start = $runsRef->{$runURL}{date};
			$seq_start =~ s/T.*//;

			for $lane (sort split(/,/, $lanesRef->{$seqURL}{$runURL}))
			{
				# do stuff to look up status on filesystem
				$run_ls = `ls /.mounts/labs/prod/archive/*/$run_name/oicr_run_complete`;
				chomp $run_ls;

				if (-e $run_ls)
				{
					$seq_complete = timeToYYMMDD( (stat($run_ls))[9] );
				}

				print processLibrary("a,$parent", $name, $dataRef) . ",$seq_start,$run_name,$lane,$seq_complete,$aligned_date,$analyzed_date,$report_date\n";
			}
		}
		return "";
	}
	else
	{
		return processLibrary("a,$parent", $name, $dataRef) . ",$seq_start,$run_name,$lane,$seq_complete,$aligned_date,$analyzed_date,$report_date";
	}
}


sub processLibrary
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	my $lib_date = $dataRef->{$name}{$type}{$leafName}{date};
	$lib_date =~ s/T.*//;
	my $parent = $dataRef->{$name}{$type}{$leafName}{parent};

	if ($parent =~ /capture,(.*)/)
	{
		$parent = $dataRef->{$name}{capture}{$1}{parent};		# skip the capture node
	}

	return processAliquot("a,$parent", $name, $dataRef) . ",$lib_date";
}


sub processAliquot
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	my $parent = $dataRef->{$name}{$type}{$leafName}{parent};

	if (exists $dataRef->{$name}{$type}{$leafName}{purpose})
	{
		$alqType =  $dataRef->{$name}{$type}{$leafName}{purpose};
	}

	return processExtraction("a,$parent", $name, $dataRef) . ",$alqType";
}


sub processExtraction
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	my $ext_date = $dataRef->{$name}{$type}{$leafName}{date};
	$ext_date =~ s/T.*//;
	my $parent = $dataRef->{$name}{$type}{$leafName}{parent};

	my $extType =  $dataRef->{$name}{$type}{$leafName}{type};

	return processTissue("a,$parent", $name, $dataRef) . ",$ext_date,$extType";
}


sub processTissue
{
	my $leaf = shift;
	my $name = shift;
	my $dataRef = shift;

	my ($alpha,$type,$leafName) = split(/,/, $leaf);

	my $donor = $name;
	my $external = $dataRef->{$name}{external_name};
	$external =~ s/,/ /g;
	my $samp = $leafName;
	$samp =~ s/^(...._...._.._.).*$/$1/;
	my $rec_date = $dataRef->{$name}{$type}{$leafName}{date};
	$rec_date =~ s/T.*//;

	return "$donor,$external,$samp,$rec_date";
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



