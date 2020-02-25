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

sub mypaint_p
{
    my $self = shift;
    return $self->install_base_dir . "/libmypaint";
}

sub babl_p
{
    my $self = shift;
    return $self->install_base_dir . "/babl";
}

sub gimp_p
{
    my $self = shift;
    return $self->install_base_dir . "/gimp-devel";
}

sub gegl_p
{
    my $self = shift;
    return $self->install_base_dir . "/gegl";
}

sub base_git_clones_dir
{
    my $self = shift;

    return $ENV{GIMPGITBUILD__BASE_CLONES_DIR}
        // ( $self->home_dir . "/Download/unpack/graphics/gimp" );
}

sub new_env
{
    my $self            = shift;
    my $gegl_p          = $self->gegl_p;
    my $babl_p          = $self->babl_p;
    my $mypaint_p       = $self->mypaint_p;
    my $PKG_CONFIG_PATH = join(
        ":",
        (
            map {
                my $p = $_;
                map { "$p/$_/pkgconfig" } qw# share lib64 lib  #
            } ( $babl_p, $gegl_p, $mypaint_p )
        ),
        ( $ENV{PKG_CONFIG_PATH} // '' )
    );
    my $XDG_DATA_DIRS =
"$gegl_p/share:$mypaint_p/share:$mypaint_p/share/pkgconfig:$babl_p/share:$ENV{XDG_DATA_DIRS}";
    return +{
        XDG_DATA_DIRS   => $XDG_DATA_DIRS,
        PKG_CONFIG_PATH => $PKG_CONFIG_PATH,
        PATH            => "$gegl_p/bin:$ENV{PATH}",
    };
}

1;

__END__

=head1 NAME

App::gimpgitbuild::API::GitBuild - common API

=head1 METHODS

=head2 babl_p

The BABL install prefix.

=head2 gegl_p

The GEGL install prefix.

=head2 gimp_p

The GIMP install prefix.

=head2 mypaint_p

The libmypaint install prefix.

=head2 new_env

Returns a hash reference of new environment variables to override.

=head2 base_git_clones_dir

The base filesystem directory path for the git repository clones.
Can be overrided by setting the C<GIMPGITBUILD__BASE_CLONES_DIR> environment
variable.

=cut
