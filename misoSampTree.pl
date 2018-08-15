#!/usr/bin/perl

use strict;
use warnings;
use JSON;

my $samples = $ARGV[0];
my $runs = $ARGV[1];

my $sampFile = $ARGV[2];
my $runFile = $ARGV[3];

my @headers = qw/donor external institute project sub_proj group_id group_desc sample sample_type purpose tis_prep seq_type library barcode sequencing identity_create sample_create stock_create aliquot_create lib_create type_chain url_chain/;


my $sampHandle;
open ($sampHandle, ">$sampFile") or die "Couldn't open >$sampFile\n";

for my $h (@headers)
{
	print $sampHandle "$h\t";
}
print $sampHandle "\n";

warn " Reading samples ($samples).\n";
open (JSON, "./$samples") or die "Couldn't open $samples\n";
my $sampJson = decode_json(<JSON>);
close JSON;

warn " Done.\n";


warn " Reading runs ($runs).\n";
open (JSON, "./$runs") or die "Couldn't open $runs\n";
my $runsJson = decode_json(<JSON>);
close JSON;
warn " Done.\n";



my %json;
my %runs;
my %lanes;
my $url;

warn " Converting sample hierarchy into hash\n";
for (my $i = 0; $i < scalar(@$sampJson); $i++)
{
	$json{$sampJson->[$i]{url}} = $sampJson->[$i];
}
warn " Done.\n";


warn " Converting run hierarchy into hash\n";
for (my $i = 0; $i < scalar(@$runsJson); $i++)
{
	$runs{$runsJson->[$i]{url}}{name} = $runsJson->[$i]{name};
	$runs{$runsJson->[$i]{url}}{barcode} = $runsJson->[$i]{barcode};
	$runs{$runsJson->[$i]{url}}{create_date} = $runsJson->[$i]{created_date};

	$runs{$runsJson->[$i]{url}}{start_date} = $runsJson->[$i]{start_date};
	$runs{$runsJson->[$i]{url}}{complete_date} = $runsJson->[$i]{completion_date};

	$runs{$runsJson->[$i]{url}}{state} = $runsJson->[$i]{state};
	$runs{$runsJson->[$i]{url}}{run_bases_mask} = $runsJson->[$i]{run_bases_mask};

	for (my $j = 0; $j <= $#{ $runsJson->[$i]{positions} }; $j++)
	{
		for (my $k = 0; $k <= $#{ $runsJson->[$i]{positions}[$j]{samples} }; $k++)
		{
			$url = $runsJson->[$i]{positions}[$j]{samples}[$k]{url};
			if (exists $lanes{$url}{$runsJson->[$i]{url}})
			{
				$lanes{$url}{$runsJson->[$i]{url}} .= "," . $runsJson->[$i]{positions}[$j]{position};
			}
			else
			{
				$lanes{$url}{$runsJson->[$i]{url}} = $runsJson->[$i]{positions}[$j]{position};
			}
		}
	}
}
warn " Done.\n";


my %data;

for my $url (keys %json)
{
	if ($json{$url}{sample_type} eq "Identity")
	{
		%data = ();

		$data{donor} = $json{$url}{name};
		$data{external} = "";
		$data{institute} = "";
		$data{group_id} = "";
		$data{group_desc} = "";
		$data{purpose} = "";
		$data{type_chain} = "$json{$url}{sample_type}";
		$data{url_chain} = "$json{$url}{id}";

		if (exists $json{$url}{attributes})
		{
			for (my $i = 0; $i <= $#{ $json{$url}{attributes} }; $i++)
			{
				if ($json{$url}{attributes}->[$i]{name} eq "Sub-project")
				{
					$data{sub_proj} = $json{$url}{attributes}->[$i]{value};
				}
				elsif ($json{$url}{attributes}->[$i]{name} eq "External Name")
				{
					$data{external} .= ",$json{$url}{attributes}->[$i]{value}";
					$data{external} =~ s/^,//;
				}
				elsif ($json{$url}{attributes}->[$i]{name} eq "Group ID")
				{
					$data{group_id} .= ",$json{$url}{attributes}->[$i]{value}";
					$data{group_id} =~ s/^,//;
				}
				elsif ($json{$url}{attributes}->[$i]{name} eq "Group Description")
				{
					$data{group_desc} .= ",$json{$url}{attributes}->[$i]{value}";
					$data{group_desc} =~ s/^,//;
				}
			}
		}

		$data{identity_create} = $json{$url}{created_date};
		$data{project} = $json{$url}{project_name};

		if (exists $json{$url}{children})
		{
			for (my $i = 0; $i <= $#{ $json{$url}{children} }; $i++)
			{
				printChildren($sampHandle, $json{$url}{children}->[$i]{url} , \%json, \%lanes, \%runs, %data);
			}
		}
	}
}



# print runs table
my @runHead = qw/name state run_bases_mask barcode create_date start_date complete_date/;

open (FILE, ">$runFile") or die "Couldn't open $runFile\n";

for my $h (@runHead)
{
	print FILE "$h\t";
}
print FILE "\n";

for my $r (sort keys %runs)
{
	for my $h (@runHead)
	{
		if ((exists $runs{$r}{$h}) and (defined $runs{$r}{$h}))
		{
			print FILE "$runs{$r}{$h}\t";
		}
		else
		{
			print FILE "\t";
		}
	}
	print FILE "\n";
}



sub printChildren
{
	my $sampHandle = shift;
	my $url = shift;
	my $json = shift;
	my $lanes = shift;
	my $runs = shift;
	my %data = @_;

	$data{type_chain} .= ",$json->{$url}{sample_type}";
	$data{url_chain} .= ",$json->{$url}{id}";

	my %runCode = (
		"Completed" => "C",
		"Failed" => "F",
		"Running" => "R",
		"Stopped" => "S",
		"Unknown" => "U",
	);

	my $purpose;

	# always update external name, institute, project, sub-project and group id/desc
	$data{project} = $json->{$url}{project_name};
	if (exists $json->{$url}{attributes})
	{
		for (my $i = 0; $i <= $#{ $json->{$url}{attributes} }; $i++)
		{
			if ($json->{$url}{attributes}->[$i]{name} eq "Sub-project")
			{
				$data{sub_proj} = $json->{$url}{attributes}->[$i]{value};
			}
			elsif ($json->{$url}{attributes}->[$i]{name} eq "External Name")
			{
				$data{external} .= ",$json->{$url}{attributes}->[$i]{value}";
				$data{external} =~ s/^,//;
			}
			elsif ($json->{$url}{attributes}->[$i]{name} eq "Institute")
			{
				$data{institute} .= ",$json->{$url}{attributes}->[$i]{value}";
				$data{institute} =~ s/^,//;
			}
			elsif ($json->{$url}{attributes}->[$i]{name} eq "Group ID")
			{
				$data{group_id} .= ",$json->{$url}{attributes}->[$i]{value}";
				$data{group_id} =~ s/^,//;
			}
			elsif ($json->{$url}{attributes}->[$i]{name} eq "Group Description")
			{
				$data{group_desc} .= ",$json->{$url}{attributes}->[$i]{value}";
				$data{group_desc} =~ s/^,//;
			}
			if ($json->{$url}{attributes}->[$i]{name} eq "Purpose")
			{
				$data{purpose} .= ",$json->{$url}{attributes}->[$i]{value}";
				$data{purpose} =~ s/^,//;
			}
		}
	}



	if ($json->{$url}{sample_type} =~ "Tissue")
	{
		$data{sample} = $json->{$url}{name};
		$data{sample_type} = $json->{$url}{sample_type};
		$data{sample_create} = $json->{$url}{created_date};


		if (exists $json->{$url}{attributes})
		{
			for (my $i = 0; $i < $#{ $json->{$url}{attributes} }; $i++)
			{
				if ($json->{$url}{attributes}->[$i]{name} eq "Tissue Preparation")
				{
					$data{tis_prep} = $json->{$url}{attributes}->[$i]{value};
				}
			}
		}

	}
	elsif ($json->{$url}{sample_type} eq "gDNA")
	{
		$data{seq_type} = $json->{$url}{sample_type};

		for (my $i = 0; $i < $#{ $json->{$url}{attributes} }; $i++)
		{
			if ($json->{$url}{attributes}->[$i]{name} eq "Purpose")
			{
				if ($json->{$url}{attributes}->[$i]{name} eq "Stock")
				{
					$data{stock_create} = $json->{$url}{created_date};
				}
				elsif ($json->{$url}{attributes}->[$i]{name} eq "Library")
				{
					$data{aliquot_create} = $json->{$url}{created_date};
				}
				
			}
		}
	}
	elsif ($json->{$url}{sample_type} eq "whole RNA")
	{
		$data{seq_type} = $json->{$url}{sample_type};

		for (my $i = 0; $i < $#{ $json->{$url}{attributes} }; $i++)
		{
			if ($json->{$url}{attributes}->[$i]{name} eq "Purpose")
			{
				if ($json->{$url}{attributes}->[$i]{name} eq "Stock")
				{
					$data{stock_create} = $json->{$url}{created_date};
				}
				elsif ($json->{$url}{attributes}->[$i]{name} eq "Library")
				{
					$data{aliquot_create} = $json->{$url}{created_date};
				}
			}
		}

	}
	elsif ($json->{$url}{sample_type} eq "Illumina PE Library")
	{
		$data{library} = $json->{$url}{name};
		$data{lib_create} = $json->{$url}{created_date};

		for (my $i = 0; $i < $#{ $json->{$url}{attributes} }; $i++)
		{
			if ($json->{$url}{attributes}->[$i]{name} eq "Barcode")
			{
				$data{barcode} = $json->{$url}{attributes}->[$i]{value};
			}
		}
	}
	elsif ($json->{$url}{sample_type} =~ /Library Seq/)
	{
		if (exists $lanes->{$url})
		{
			for my $r (sort keys %{ $lanes->{$url} })
			{
				$data{sequencing} .= ";$runs->{$r}{name}($runCode{$runs->{$r}{state}}):$lanes->{$url}{$r}";
			}
			$data{sequencing} =~ s/^;//;
		}
	}




	if (exists $json->{$url}{children})
	{
		for (my $i = 0; $i <= $#{ $json->{$url}{children} }; $i++)
		{
			printChildren($sampHandle, $json->{$url}{children}->[$i]{url}, $json, $lanes, $runs, %data);
		}
	}
	else
	{
		for my $val (@headers)
		{
			if (exists $data{$val})
			{
				print $sampHandle "$data{$val}\t";
			}
			else
			{
				print $sampHandle "\t";
			}
		}
		print $sampHandle "\n";
	}

}






