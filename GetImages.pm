package HTTP::GetImages;
our $VERSION=0.1;

=head1 NAME

HTTP::GetImages

=head1 DESCRIPTION

Recover and locally store all the images found in documents at passed URIs.

=head1 SYNOPSIS

	use HTTP::GetImages;
	new HTTP::GetImages (
		qw(
			http://www.google.co.uk
			http://www.google.com/
		)
	);

=head1 DEPENDENCIES

	strict;
	Carp;
	LWP::UserAgent;
	HTTP::Request;
	HTML::TokeParser;

=cut

use strict;
use Carp;
use LWP::UserAgent;
use HTTP::Request;
use HTML::TokeParser;

=head1 PACKAGE GLOBAL VARIABLE

=item $chat

Set it if you'd like a real-time report to C<STDERR>.

=cut

our $chat=1;

=head1 CONSTRUCTOR METHOD new

Besides the class reference, accepts the path to the directory in which to store images, the remaining paramters being interpreted as an array of URLs.

Returns a blessed hash, keys of which are the original URLs of the images, values of which are the current filenames.

=cut

sub new { my ($class,$dir,@urls) = (shift,shift,@_);
	warn "$class::new requires a directory in which store the images as its second argument." and return undef if not defined $dir;
	warn "$class::new requires at least one URL to saerch for images as its third argument." and return undef if not defined @urls;
	my $self={};
	bless $self,$class;

	PAGE:
	foreach my $page_url (@urls){
		warn "*** Parsing $page_url\t\t\t\t"  if defined $chat;
		my $doc = &get_document($page_url);
		my $p = new HTML::TokeParser( \$doc ) or warn "* Couldn't create parser" and next PAGE;
		while (my $token = $p->get_token){
			if (@$token[1] eq 'img'){
				my $img_url = &abs_url( $page_url, @$token[2]->{src} );
				$self->{$img_url} = save_img ( $dir,$img_url,get_document($img_url));
			}
		}
	}
	return $self;
}


#
# SUB get_document
# Accepts a URL, returns the source of the document at the URL
#
sub get_document{
	my $url = shift;									# Recieve as argument the URL to access
	my $ua = LWP::UserAgent->new;						# Create a new UserAgent
	$ua->agent('Mozilla/25.0 (getPage0.2');				# Give it a type name
	warn "Attempting to access $url...\n"  if defined $chat;
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


#
# SUB save_img
# Accepts the dir in which to store the image, the original URL (for name purposes) and the actual image source
# Returns the path the image was saved at.
#
sub save_img { my ($dir,$orig_url,$img) = (shift,shift,shift);
	local *OUT;
	my $filename = $orig_url;
	$filename =~ s/^.*?([^.\/]+\.)(jpg|jpeg|tiff|gif|png\xbm)$/$1$2/i;
	$filename = $dir.'/'.$filename;
	warn "Saving image as $filename...\n"  if defined $chat;
	open OUT,">$filename";
	binmode OUT;
	print OUT $img;
	close OUT;
	return $filename;
}


#
# SUB abs_url returns an absolute URL for a $child_url linked from $parent_url
#
sub abs_url { my ($parent_url,$child_url) = (shift,shift);
	if ($child_url =~ m|^/|){
		# Add site base
		$child_url =~ m|(http://[^/]+)|i;
		$child_url = $1 .$child_url;
		warn "Made URL: $child_url (added server)" if defined $chat;
	}

	elsif ($child_url !~ m|^http://|i){
		# Add page base
		my $base = $parent_url;
		$base =~ s/[\w\d-_]+\.html?$//i;
		$child_url = $base.'/'.$child_url;
		warn "Made URL: $child_url (completed relative path)" if defined $chat;
	}

	else {
		warn "Left URL alone: $child_url" if defined $chat;
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

