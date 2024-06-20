#!/usr/bin/perl -w

# NB This script is designed to be run from the ~/lib/epm/coar_vocabs/bin/ directory.
# It is a standalone script which doesn't connect to an EPrints repository at all, although it does have some
# knowledge of the EPrint phrases XML format.

use FindBin;
use lib "$FindBin::Bin/../../../../perl_lib";

######################################################################
#
#
######################################################################

=pod

=head1 NAME

B<process_coar_vocabs.pl> - Generate namedset and language specific phrase files for the COAR vocabularies.

=head1 SYNOPSIS

B<process_coar_vocabs.pl> [B<SKOS-file> B<namedset-name>] [B<options>] 

=head1 DESCRIPTION

This script parses the latest COAR SKOS files that describe the access_rights, resource_types and version_types.
The SKOS files contain definitions for many languages. The script will create phrase files for any defined languages
for the specified repository.

=head1 ARGUMENTS

=over 8

=item B<skos-file> 

The path to a skos file to be processed. Must also have accompanying 'namedset' argument.

=back

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print the full manual page and then exit.

=item B<--verbose>

Explain in detail what is going on.

=back   


=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

use File::Basename;
use File::Path qw/make_path/;
use File::Temp;

use XML::LibXML;
use LWP::UserAgent;
use Data::Dumper;

my $source_dir = dirname(__FILE__) . "/../files/sources/clean/";
my $output_dir = dirname(__FILE__) . "/../files/outputs";

binmode *STDOUT, ':utf8'; # debugging 


my $verbose = 0;
my $help = 0;
my $man = 0;
my $cached_file_dir;
my $vocabs_to_generate;
my $langs_to_generate;

# The non-versioned URLs link to the most recent adopted vocab.
my %vocabs = (
	coar_access_rights => "https://vocabularies.coar-repositories.org/access_rights/access_rights.nt",
	coar_resource_types => "https://vocabularies.coar-repositories.org/resource_types/resource_types.nt",
	coar_version_types => "https://vocabularies.coar-repositories.org/version_types/version_types.nt",
);

# In the vocabulary files there are lines relating to the vocab itself. These shouldn't be options for the value itself,
# and shouldn't exist in the phrase files either.
my @subjects_to_exclude = qw(
	http://purl.org/coar/access_right/scheme
);


Getopt::Long::Configure("permute");

GetOptions( 
	'help|?' => \$help,
	'man' => \$man,
	'verbose' => \$verbose,
	'cached-file-dir=s' => \$cached_file_dir,
	'vocab=s@' => \$vocabs_to_generate,
	'lang=s@' => \$langs_to_generate,
) || pod2usage( 2 );
pod2usage( 1 ) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;
#pod2usage( 2 ) if( scalar @ARGV != 2 ); 

# Set STDOUT to auto flush (without needing a \n)
$|=1;


foreach my $v ( @$vocabs_to_generate )
{
	if( !defined $vocabs{$v} )
	{
		print STDERR "Requested vocab '$v' not defined. Please specify none or more of:\n" .
			join( "\n", map { "\t--vocab $_" } keys %vocabs ) ,"\n";
		exit 1;
	}
}

$vocabs_to_generate = [ keys %vocabs ] if scalar @$vocabs_to_generate == 0;

my $skos_file = $ARGV[0];
my $skos_name = $ARGV[1];

# SKOS file supplied on commandline
if( defined $skos_file )
{
	if( ! -f $skos_file )
	{
		print STDERR "ERROR: SKOS file $skos_file not found\n";
		exit 1;
	}
	if( !defined $skos_name )
	{
		# get filename without extension
		( $skos_name ) = $skos_file =~ /([^\/]+?)(?:\.\S+)?$/;
		$skos_name = "coar_$skos_name";
	}

	open( my $fh, '<', $skos_file ) or die "Can't open $skos_file: $!";

	# Somewhere to stash the parsed structure - which in our use-case isn't massive.
	my $skos = parse_skos( $fh );
	close( $fh );

	print "Processing $skos_file as $skos_name\n" if $verbose;
	process_skos( $skos, $skos_name );

	exit;
}

# No specific vocab defined, process them all!
foreach my $vocab ( @$vocabs_to_generate )
{
	print "Generating $vocab\n" if $verbose;

	my $skos;

	if( defined $cached_file_dir )
	{
		if( !-d $cached_file_dir )
		{
			print STDERR "--cache-file-dir $cached_file_dir is not a directory\n";
			exit 1;
		}

		my ( $skos_file ) = $vocab =~ /^coar_(.*)$/;
		$skos_file = "$cached_file_dir/$skos_file.nt";

		open( my $fh, '<', $skos_file ) or die "Can't open $skos_file: $!";
		print "Using file\n\t$skos_file\n" if $verbose;
		$skos = parse_skos( $fh );
		close( $fh );
	}
	else
	{	
		print "Vocab URL: $vocabs{$vocab}\n" if $verbose;

		my $skos_file = get_skos_from_url( $vocabs{$vocab} );
		exit 1 if !defined $skos_file;
		$skos = parse_skos( $skos_file );
	}
	process_skos( $skos, $vocab );
}

exit;

sub parse_skos
{
	my( $file ) = @_;

	my $skos_h = {};
	$skos_h->{LANGS} = {};
	$skos_h->{SUBJECTS} = {};
	$skos_h->{PREDICATES} = {};

	# From: https://en.wikipedia.org/wiki/N-Triples
	# Line starting with a hash is a comment.
	# Other lines are a 'statement' line, consisting of four parts, separated by whitespace:
	# - subject (URI or blank-node)
	# - predicate (URI)
	# - object (URI, blank-node or literal)
	# - full-stop (termination of statement)
	#
	# URIs are wrapped in '< >'s
	# Blank-nodes are of the form  _:[alphanumic string]
	# Literals are double-quote escaped, backslash-escaped ASCII strings. Optional suffix of '@language' (two-character - RFC3066) or '^^datatype' (not both).
	#
	# From: https://www.w3.org/TR/n-triples/#sec-literals:
	# ... If there is no language tag, there may be a datatype IRI, preceded by '^^' (U+005E U+005E). If there is no datatype IRI and no language tag it is a 
	# simple literal and the datatype is http://www.w3.org/2001/XMLSchema#string.

	my $lineno = 0;
	while (defined(my $line = <$file>)) {
	LINE:
		($line, my @extra) = split(/\r\n|\r|\n/, $line, 2);
		$lineno++;

		next unless (defined($line) and length($line));
		next unless ($line =~ /\S/);
		chomp($line);
		$line =~ s/^\s*//;
		$line =~ s/\s*$//;
		next if ($line =~ /^#/);

		my( $s, $p, $o ) = $line =~ /^(\S+)\s(\S+)\s(.*?)\s\.$/;

		$s =~ s/^\<|>$//g;
		$p =~ s/^\<|>$//g;

		# object can contain                             a literal  or   a URI                a language                        or a datatype
		my( $o_, $iri, $lang, $datatype ) = $o =~ /^(?: (?:"(.*?)") | (?:<([^>]*?)>) ) (?: (?:@([a-z]+(?:-[a-zA-Z0-9]+)*)) | (?:\^\^\<(.*?)\>) )?$/x;

		if( defined $o_ )
		{
			# decode 4-byte unicode sequences
			$o_ =~ s{ \\u([0-9A-F]{4}) }{ chr(oct('0x' . $1 )) }xeg;
			# decode 8-byte unicode sequences
			$o_ =~ s{ \\U([0-9A-F]{8}) }{ chr(oct('0x' . $1 )) }xeg;
		}

		$lang ||= "DEFAULT";
		my $val = defined $o_ ? $o_ : $iri;
		
		# some subject/predicate combinations can have multiple values e.g. altName
#		if( defined $skos_h->{$s}->{$p}->{$lang} )
#		{
#			my $val = defined $o_ ? $o_ : $iri;
#
#			if( ref $skos_h->{$s}->{$p}->{$lang} eq "ARRAY" )
#			{
#				push @{ $skos_h->{$s}->{$p}->{$lang} }, $val;
#			}
#			else
#			{
#				my @tmp = ( $skos_h->{$s}->{$p}->{$lang} );
#				push @tmp, $val;
#				$skos_h->{$s}->{$p}->{$lang} = \@tmp;
#			}
#		}
#		else
#		{
#			$skos_h->{$s}->{$p}->{$lang} = ( defined $o_ ? $o_ : $iri );
#		}
		$skos_h->{SUBJECTS}->{$s}++;

		if( defined $skos_h->{LANGS}->{$lang}->{$s}->{$p} )
		{
			if( ref $skos_h->{LANGS}->{$lang}->{$s}->{$p} eq "ARRAY" )
			{
				push @{ $skos_h->{LANGS}->{$lang}->{$s}->{$p} }, $val;
			}
			else
			{
				my @tmp = ( $skos_h->{LANGS}->{$lang}->{$s}->{$p} );
				push @tmp, $val;
				$skos_h->{LANGS}->{$lang}->{$s}->{$p} = \@tmp;
			}
		}
		else
		{
			$skos_h->{LANGS}->{$lang}->{$s}->{$p} = ( defined $o_ ? $o_ : $iri );
		}
		$skos_h->{PREDICATES}->{$p}++;
	}
	return $skos_h;
}

# returns a tempfile or undef.
sub get_skos_from_url
{
	my( $url ) = @_;

	my $tmpfile = File::Temp->new;

	my $ua = LWP::UserAgent->new( agent => "EPrints-dev" );
	$ua->env_proxy;

        my $r = $ua->get( $url,
                ":content_file" => $tmpfile->filename
        );

	if( $r->is_success )
	{
		seek( $tmpfile, 0, 0 );
		return $tmpfile;
	}
	else
	{
		print STDERR "Failed to retrieve $url: " . $r->code . " " . $r->message,"\n";
	}
}

sub process_skos
{
	my( $skos, $namedset, $langs ) = @_;

	my @namedset_opts = keys %{$skos->{SUBJECTS}};

	# get rid of schema (and possibly other unwanted subjects)
	my %excl;
	@excl{@subjects_to_exclude} = undef;
	@namedset_opts = grep { not exists $excl{$_} } @namedset_opts;	

	save_namedset_file( "$output_dir/cfg/namedsets/$namedset", \@namedset_opts );

	foreach my $lang ( keys $skos->{LANGS} )
	{
		next if $lang eq "DEFAULT";
		if( defined $langs_to_generate && !(/^$lang$/ ~~ @$langs_to_generate ) )
		{
			print "Skipping $lang\n" if $verbose;
			next;
		}
		print "Generating $lang\n";

		my $doc = create_phrase_document();
		add_comment( $doc, "COAR vocabulary modified on " . get_schema_modified_date( $skos ) );

		foreach my $p ( keys $skos->{LANGS}->{$lang} )
		{
			print "Processing $p\n" if $verbose;

			if( exists $skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#prefLabel'} )
			{
				# Deal with bad SKOS file (see README)
				# This should always be a single value. If it isn't, there's probably a problem with the SKOS input
				if( ref $skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#prefLabel'} eq "ARRAY" )
				{
					print STDERR "ERROR: repeated 'prefLabel' for $p (lang: $lang)\n";
					print STDERR "\tThis normally indicates that there is a problem with the source SKOS files. You may need to review them manually\n";
					exit 1;
				}
				add_phrase( $doc,
					$namedset . "_typename_" . $p,
					$skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#prefLabel'}
				);
			}

			if( exists $skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#altLabel'} )
			{
				my $comment;
				if( ref $skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#altLabel'} eq "ARRAY" )
				{
					$comment = "AltLabels for $p:\n\t" . join( "\n\t", @{$skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#altLabel'}} );
				}
				else
				{
					$comment = "AltLabel for $p: " . $skos->{LANGS}->{$lang}->{$p}->{'http://www.w3.org/2004/02/skos/core#altLabel'};
				}
				add_comment( $doc, $comment );
			}
		}

		#print $doc->toString(1);
		my $phrase_path = "$output_dir/cfg/lang/$lang/phrases";
		print $phrase_path,"\n";
		save_phrase_file( $doc, $phrase_path, "$namedset.xml" );	
	}
	
}

sub save_namedset_file
{
	my( $fullpath, $options ) = @_;

print "SAVING TO $fullpath\n";

	if( !defined $fullpath )
	{
		print STDERR "file path not supplied to save namedset file\n";
		return;
	}

	if( -f "$fullpath" )
	{
		print STDERR "NOTE: Overwriting existing namedset file\n"
	}

	open( my $fh, ">", "$fullpath" ) or die "Cannot open $fullpath for writing";
	print $fh join( "\n",@$options);
	close( $fh );
}

sub get_schema_modified_date
{
	my( $skos ) = @_;

	#if( exists $skos->{'http://purl.org/coar/access_right/scheme'}->{'http://purl.org/dc/terms/modified'} )
	#{
	#	return $skos->{'http://purl.org/coar/access_right/scheme'}->{'http://purl.org/dc/terms/modified'}->{DEFAULT};
	#}
	if( exists $skos->{LANGS}->{DEFAULT}->{'http://purl.org/coar/access_right/scheme'}->{'http://purl.org/dc/terms/modified'} )
	{
		return $skos->{LANGS}->{DEFAULT}->{'http://purl.org/coar/access_right/scheme'}->{'http://purl.org/dc/terms/modified'};
	}
}

sub create_phrase_document
{
	my $doc = XML::LibXML->createDocument( "1.0", "utf-8" );
	$doc->setStandalone(0);
	my $dtd = $doc->createInternalSubset( "phrases", undef, "entities.dtd" );

	my $phrases = $doc->createElement( "phrases" );
	$doc->setDocumentElement( $phrases );
	$phrases->setNamespace( "http://www.w3.org/1999/xhtml", undef, 0 );
	$phrases->setNamespace( "http://eprints.org/ep3/phrase", "epp", 1 );
	$phrases->setNamespace( "http://eprints.org/ep3/control", "epc", 0 );

	return $doc;
}

sub add_phrase
{
	my( $doc, $id, $content ) = @_;

	my $phrase = $doc->createElement( "phrase" );
	$phrase->setNamespace( "http://eprints.org/ep3/phrase", "epp", 1 );
	$phrase->setAttribute( "id", $id );
	$phrase->appendTextNode( $content );

	$doc->documentElement->appendChild( $phrase );

}

sub add_comment
{
	my( $doc, $comment ) = @_;

	$doc->documentElement->appendChild( $doc->createComment( $comment ) );
}

sub save_phrase_file
{
	my( $doc, $path, $filename ) = @_;

	if( !-d $path )
	{
		make_path($path);
	}

	return $doc->toFile( "$path/$filename", 1 ); # include indentation
}


=head1 COPYRIGHT

=for COPYRIGHT BEGIN

#TODO

=for COPYRIGHT END

=for LICENSE BEGIN

#TODO

=for LICENSE END

