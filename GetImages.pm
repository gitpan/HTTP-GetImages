package HTTP::GetImages;
our $VERSION=0.21;

=head1 NAME

HTTP::GetImages

=head1 DESCRIPTION

Recover and locally store images from the web, including those linked by anchor and image map.

Version 0.2+ also gets images from C<A>nchor elements' and image-map C<AREA> elements' C<HREF>/C<SRC>. attributes.

=head1 SYNOPSIS

	use HTTP::GetImages;
	new HTTP::GetImages (
		'/images/new',
		qw( http://www.google.co.uk http://www.google.com/ )
	);

=head1 DEPENDENCIES

	strict;
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
no strict 'refs';

=head1 PACKAGE GLOBAL VARIABLE

=item $chat

Set it if you'd like a real-time report to C<STDERR>.
Defaults to off.

=cut

our $chat = undef;

=item $EXTENSIONS_RE

A regular expression 'or' list of image extensions to match.

Will be applied at the end of a filename, after a point, and is insensitive to case.

Defaults to C<(jpg|jpeg|bmp|gif|png|xbm|xmp)>.

=cut

our $EXTENSIONS_RE = '(jpg|jpeg|bmp|gif|png|xbm|xmp)';

=head1 CONSTRUCTOR METHOD new

Besides the class reference, accepts the path to the directory in which to store images (no trailing oblique necessary), the remaining paramters being interpreted as an array of URLs.

Returns a blessed hash, keys of which are:

=item DONE

a hash keys of which are the original URLs of the images, value being are the local filenames.

=item FAILED

a hash, keys of which are the failed URLs, values being short reasons.

=cut

sub new { my ($class,$dir,@urls) = (shift,shift,@_);
	warn "$class::new requires a directory in which store the images as its second argument." and return undef if not defined $dir;
	warn "$class::new requires at least one URL to saerch for images as its third argument." and return undef if not defined @urls;
	warn "Usage: $class::new (\$dir,\@url) " and return undef if not defined $class;

	my $self={};
	$self->{DONE} = {};
	$self->{FAILED} = {};
	bless $self,$class;

	PAGE:
	foreach my $page_url (@urls){
		if (exists $self->{FAILED}->{$page_url} or exists $self->{DONE}->{$page_url}){
			warn "Already done.\n" if defined $chat;
			next PAGE;
		}
		warn "*** Parsing $page_url\t\t\t\t"  if defined $chat;

		my $doc = &get_document($page_url)
			or warn "* Couldn't create parser"
			and ($self->{FAILED}->{$page_url} = "Agent couldn't open page")
			and next PAGE;

		my $p = new HTML::TokeParser( \$doc )
			or warn "* Couldn't create parser"
			and ($self->{FAILED}->{$page_url} = "Couldn't create agent parser")
			and next PAGE;

		TOKE:
		while (my $token = $p->get_token){
			next TOKE if @$token[1] !~ m/^(img|area|a)$/;
			next TOKE if @$token[0] ne 'S';	# How does that effect well-formed XHTML?

			my $img_url='';

			# Get an IMG src
			if (@$token[1] eq 'img'){
				$img_url = &abs_url( $page_url, @$token[2]->{src} ) ;
			}

			# Get an AREA href
			elsif (@$token[1] eq 'area'){
				$img_url = &abs_url( $page_url, @$token[2]->{href} ) ;
			}

			# Get an image in an Anchor element
			elsif (@$token[1] eq 'a' and @$token[0] eq 'S'){
				my $href = @$token[2]->{href};
				# Parse up to end of the Anchor element
				while ($token = $p->get_token and not (@$token[0] eq 'E' and @$token[1] eq 'a')){
					$img_url = &abs_url( $page_url, @$token[2]->{src} ) if @$token[1] eq 'img';
					# Act now to process the gained URL as below
					if ($img_url =~ m/\.html?/i){
						push @urls,$img_url
					} elsif ($img_url =~ m|(\.$EXTENSIONS_RE)$|i) {
						$self->{DONE}->{$img_url} = $self->_save_img( $dir,$img_url,get_document($img_url));
					}
				}
			} # End if

			# If we got a new URI
			if (not exists $self->{FAILED}->{$page_url} and not exists $self->{DONE}->{$page_url}){
				# Act now to process the gained URL as above
				if ($img_url =~ m/\.html?/i){
					warn "Will remember to parse $img_url later" if defined $chat;
					push @urls,$img_url
				} elsif ($img_url =~ m|(\.$EXTENSIONS_RE)$|i) {
					$self->{DONE}->{$img_url} = $self->_save_img( $dir,$img_url,get_document($img_url));
				}
			}

		} # Next while TOKE
	} # Next for PAGE
	return $self;
} # End sub new





#
# SUB get_document
# Accepts a URL, returns the source of the document at the URL
#
sub get_document{
	my $url = shift;									# Recieve as argument the URL to access
	my $ua = LWP::UserAgent->new;						# Create a new UserAgent
	$ua->agent('Mozilla/25.0 (getPage0.2');				# Give it a type name
	warn "Attempting to access <$url>...\n"  if defined $chat;
	my $req = new HTTP::Request('GET', $url);		# Format URL request
	my $res = $ua->request($req);					# $res is the object UA returned
	if ($res->is_success()) {							# If successful
		warn "...ok.\n" if defined $chat;
		return $res->content;							# $res->content  is the HTML the UA returned from the URL
	} else {
		warn"...failed.\n"  if defined $chat;
		return "";
	}
}



=head1 PRIVATE METHOD _save_img

Accepts the dir in which to store the image,
the image's URL (won't store same image twice)
and the actual image source.

Returns the path the image was saved at.

=cut

sub _save_img { my ($self,$dir,$url,$img) = (shift,shift,shift,shift);
	local *OUT;
	# Remvoe any file path from the $url
	if (exists $self->{DONE}->{$url} or exists $self->{FAILED}->{$url}){
		warn "Already got this one ($url), not saving.\n" if defined $chat;
		return undef;
	}
	$url =~ m|/[^./]+(\.$EXTENSIONS_RE)$|i;
	my $ext = $1;
	my $filename = $dir.'/'.(join'',localtime).$ext;
	warn "Saving image as $filename...\n"  if defined $chat;
	open OUT,">$filename" or warn "Couldn't open to save <$filename>!";
	binmode OUT;
	print OUT $img;
	close OUT;
	return $filename;
}


#
# SUB abs_url returns an absolute URL for a $child_url linked from $parent_url
#
sub abs_url { my ($parent_url,$child_url) = (shift,shift);
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

