package HTTP::GetImages;
our $VERSION=0.23;

=head1 NAME

HTTP::GetImages

=head1 DESCRIPTION

Recover and locally store images from the web, including those linked by anchor and image map.

Version 0.2+ also gets images from C<A>nchor elements' and image-map C<AREA> elements' C<HREF>/C<SRC>. attributes.

Version 0.23+ allows a limitation on the image size retreived.

=head1 SYNOPSIS

	use HTTP::GetImages;
	new HTTP::GetImages (
		'/image/save/dir',
		['http://www.getthese.com/all','http://get.this/'],
		['http://www.somewhere/ignorethis.html','http://and.this.html']
	);

	new HTTP::GetImages (
		'/image/save/dir',
		['http://www.getthese.com/all','http://get.this/'],
		['ALL'],
		'http://www.getthses.com/all/useTHISasROOT/',
		$minsize
	);

	print "\nFailed these URLs:-\n";
	foreach (keys %{$self->{FAILED}})	{ print "\t$_\n" }

	print "\nIgnored these URLs:-\n";
	foreach (keys %{$self->{IGNORED}})	{ print "\t$_\n" }

=head1 DEPENDENCIES

	strict;
	warnings;
	Carp;
	LWP::UserAgent;
	HTTP::Request;
	HTML::TokeParser;

=cut

use LWP::UserAgent;
use HTTP::Request;
use HTML::TokeParser;
use Carp;
use strict;
use warnings;
no strict 'refs';

=head1 PACKAGE GLOBAL VARIABLE

=head2 $CHAT

Set to above zero if you'd like a real-time report to C<STDERR>.
Defaults to off.

=cut

our $CHAT = 0;
$CHAT =0;

=head2 $EXTENSIONS_RE

A regular expression 'or' list of image extensions to match.

Will be applied at the end of a filename, after a point, and is insensitive to case.

Defaults to C<(jpg|jpeg|bmp|gif|png|xbm|xmp)>.

=cut

our $EXTENSIONS_RE = '(jpg|jpeg|bmp|gif|png|xbm|xmp)';

=head2 $NEWNAMES

Set to above zero to save files with new names; defaults to using original names.

=cut

our $NEWNAMES = 0;

=head1 CONSTRUCTOR METHOD new

Besides the class reference, accepts:

=item 1.

the path to the directory in which to store images (no trailing oblique necessary);

=item 2.

reference to array of URLs to process;

=item 3.

reference to array of URLs to ignore.

If one of these is C<ALL>, then will ignore all B<HTML> documents not in the referenced array of URLs to process.
If one of these is C<NONE>, will ignore no documents.

Returns a blessed hash, keys of which are:

=item 4.

The minimum path the URL must contain.

=item 5.

The minimum size an image must be to be saved.

=item DONE

a hash keys of which are the original URLs of the images, value being are the local filenames.

=item FAILED

a hash, keys of which are the failed URLs, values being short reasons.

=cut

sub new { my ($class,$dir,$dodo,$dont,$MINURL,$MINIMGSIZE) = (shift,shift,shift,shift,shift,shift);
	warn "Usage: \$class::new (\$dir,\\\@do,\\\@dont) " and return undef if not defined $class;
	warn "$class::new requires a directory in which store the images as its first argument." and return undef if not defined $dir;
	warn "$class::new requires at least one URL to saerch for images as its seoncd argument." and return undef if not defined $dodo;
	warn "Usage: \$class::new (\$dir,\@do,\@dont) " and return undef if ref $dodo ne 'ARRAY' or (defined $dont and ref $dont ne 'ARRAY');

	my $self={};
	$self->{DONE} = {};
	$self->{FAILED} = {};
	bless $self,$class;

	$self->{MINIMGSIZE} = $MINIMGSIZE if defined $MINIMGSIZE;
	warn "Minimum image size defined as $self->{MINIMGSIZE}.\n" if $CHAT;

	$self->{MINURL} = $MINURL if defined $MINURL;
	warn "URL must being with $MINURL ..." if $CHAT;

	my @urls;

	foreach (@$dodo){ push @urls,$_; $self->{DO}->{$_}=1; }
	undef $dodo;
	foreach (@$dont){ $self->{IGNORE}->{$_} = '1' }
	undef $dont;


	DOC:
	while (my $doc_url = shift @urls){
		warn "-"x60,"\n" if $CHAT;
		my ($doc,$p);

		if (exists $self->{MINURL} and $doc_url !~ /^$self->{MINURL}/){
			warn "URL out of scope, ignoring $doc_url\n" if $CHAT;
			next DOC;
		}

		if (exists $self->{FAILED}->{$doc_url} or exists $self->{DONE}->{$doc_url}){
			warn "Already done $doc_url.\n" if $CHAT;
			next DOC;
		}

		if (exists $self->{IGNORE}->{$doc_url}){
			warn "In IGNORE list: $doc_url.\n" if $CHAT;
			next DOC;
		}

		# Not in do list, not an image, not run with IGNORE NONE option
		if (not exists $self->{DO}->{$doc_url} and $doc_url !~ m|(\.$EXTENSIONS_RE)$|i
		and not exists $self->{IGNORE}->{NONE}){
			warn "Not in DO list - ignoreing $doc_url .\n" if $CHAT;
			$self->{IGNORE}->{$doc_url} = "Ignoring";
			next DOC;
		}

		unless ($doc = $self->get_document($doc_url)){
			$self->{FAILED}->{$doc_url} = "Agent couldn't open page";
			next DOC;
		}

		# If an image, save it
		if ($doc_url =~ m|(\.$EXTENSIONS_RE)$|i) {
			$self->{DONE}->{$doc_url} = $self->_save_img($dir,$doc_url,$doc);
			next DOC;
		} else {
			$self->{DONE}->{$doc_url} = "Did HTML.";
		}

		# Otherwise try to parse it
		unless ($p = new HTML::TokeParser( \$doc )){
			warn "* Couldn't create parser from \$doc\n" if $CHAT;
			$self->{FAILED}->{$doc_url} = "Couldn't create agent parser";
			next DOC;
		}
		warn "OK - parsing document $doc_url ...\n" if $CHAT;

		while (my $token = $p->get_token){
			if (@$token[1] eq 'img'){
				warn "*** Found image: @$token[2]->{src}\n" if $CHAT;
				my $uri = &abs_url( $doc_url, @$token[2]->{src} );
				if (not exists $self->{IGNORE0}->{$uri} and not exists $self->{DONE}->{$uri} and not exists $self->{FAILED}->{$uri}){
					unshift @urls, $uri;
				}
			}
			elsif (@$token[1] eq 'area' or @$token[1] eq 'a' and @$token[0] eq 'S'){
				warn "*** Found link: @$token[2]->{href}\n" if $CHAT;
				my $uri = &abs_url( $doc_url, @$token[2]->{href} );
				if (not exists $self->{IGNORE}->{$uri} and not exists $self->{DONE}->{$uri} and not exists $self->{FAILED}->{$uri}){
					unshift @urls, $uri;
				}
			}
		}

	} # Next DOC

	return $self;
} # End sub new





#
# SUB get_document
# Accepts a URL, returns the source of the document at the URL
#
sub get_document { my ($self,$url) = (shift,shift);		# Recieve as argument the URL to access
	my $ua = LWP::UserAgent->new;						# Create a new UserAgent
	$ua->agent('Mozilla/25.0'.(localtime).' (PERL HTTP::GetImages $VERSION');	# Give it a type name
	warn "Attempting to access <$url>...\n"  if $CHAT;
	my $req = new HTTP::Request('GET', $url) 			# Format URL request
		or warn "...could not GET.\n" and return undef;
	my $res = $ua->request($req);						# $res is the object UA returned
	if (not $res->is_success()) {							# If successful
		warn"...failed.\n"  if $CHAT;
		return undef
	}
	warn "...ok.\n" if $CHAT;
	# Test size
	if ($url =~ m|(\.$EXTENSIONS_RE)$|i) {
		$_ = length ($res->content);
		warn "Image file size $_ bytes\n" if $CHAT;
		if (exists $self->{MINIMGSIZE} and  $_ < $self->{MINIMGSIZE}){
			warn "Image size too small, ignoring.\n" if $CHAT;
			$self->{IGNORE}->{$url} = "Size $_ bytes is too small.";
			return undef;
		}
	}

	return $res->content;							# $res->content  is the HTML the UA returned from the URL
}



=head1 PRIVATE METHOD _save_img

Accepts the dir in which to store the image,
the image's URL (won't store same image twice)
and the actual image source.

Returns the path the image was saved at.

=cut

sub _save_img { my ($self,$dir,$url,$img) = (shift,shift,shift,shift);
	local *OUT;
	my $filename;
	# Remvoe any file path from the $url
	if (exists $self->{DONE}->{$url} or exists $self->{FAILED}->{$url}){
		warn "Already got this one ($url), not saving.\n" if $CHAT;
		return undef;
	}
	$url =~ m|/([^./]+)(\.$EXTENSIONS_RE)$|i;
	if ($NEWNAMES){
		$filename = $dir.'/'.(join'',localtime).$2;
	} else {
		$filename = "$dir/$1$2";
	}
	warn "Saving image as <$filename>...\n"  if $CHAT;
	open OUT,">$filename" or warn "Couldn't open to save <$filename>!" and return "Failed to save.";
		binmode OUT;
		print OUT $img;
	close OUT;
	warn "...ok.\n" if $CHAT;
	return $filename;
}


#
# SUB abs_url returns an absolute URL for a $child_url linked from $parent_url
#
# DOC http://www.netverifier.com/pin/nicolette/jezfuzchr001.html
# SRC /pin/nicolette/jezfuzchr001.jpg
#
sub abs_url { my ($parent_url,$child_url) = (shift,shift);
	my $hack;
	if ($child_url =~ m|^/|) {
		$parent_url =~ s|^(http://[\w.]+)?/.*$|$1|i;
		return $parent_url.$child_url;
	}
	if ($child_url =~ m|^\.\.\/|i){
		$parent_url =~ s/\/[^\/]+$//;	# Strip filename
		while ($child_url=~s/^\.\.\///gs ){
			$parent_url =~s/[^\/]+\/?$//;
		}
		$child_url = $parent_url.$child_url;
	} elsif ($child_url !~ m/^http:\/\//i){
		# Assume relative path needs dir
		$parent_url =~ s/\/[^\/]+$//;	# Strip filename
		$child_url = $parent_url .'/'.$child_url;
	}
	return $child_url;
}









1; # Return a true value for 'use'

=head1 SEE ALSO

Every thing and every one listed above under DEPENDENCIES.

=head1 AUTHOR

Lee Goddard (LGoddard@CPAN.org) 05/05/2001 16:08

=head1 COPYRIGHT

Copyright 2000-2001 Lee Goddard.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

