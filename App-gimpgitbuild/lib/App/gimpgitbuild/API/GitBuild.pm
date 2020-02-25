package App::gimpgitbuild::API::GitBuild;

use strict;
use warnings;
use 5.014;

use Moo;

has home_dir         => ( is => 'lazy' );
has install_base_dir => ( is => 'lazy' );

sub _build_home_dir
{
    return $ENV{HOME};
}

sub _build_install_base_dir
{
    my $self = shift;
    return $self->home_dir . "/apps/graphics";
}

1;

__END__

=head1 NAME

App::gimpgitbuild::API::GitBuild - common API

=head1 FUNCTIONS

=head2 fill_in

=cut
