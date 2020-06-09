package App::gimpgitbuild::Command::build;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

use File::Which qw/ which /;
use Path::Tiny qw/ path tempdir tempfile cwd /;

use App::gimpgitbuild::API::GitBuild ();
use Git::Sync::App                   ();

sub description
{
    return "build gimp from git";
}

sub abstract
{
    return shift->description();
}

sub opt_spec
{
    return ( [ "mode=s", "Mode (e.g: \"clean\")" ], );

=begin foo
    return (
        [ "output|o=s", "Output path" ],
        [ "title=s",    "Chart Title" ],
        [ 'exec|e=s@',  "Execute command on the output" ]
    );
=end foo

=cut

}

sub _do_system
{
    my ($args) = @_;

    my $cmd = $args->{cmd};
    print "Running [@$cmd]\n";
    if ( system(@$cmd) )
    {
        die "Running [@$cmd] failed!";
    }
}

sub _check
{
    return ( length( $ENV{SKIP_CHECK} ) ? "true" : "make check" );
}

my $skip_builds_re;

BEGIN
{
    my $KEY = "GIMPGITBUILD__SKIP_BUILDS_RE";
    if ( exists $ENV{$KEY} )
    {
        my $re_str = $ENV{$KEY};
        $skip_builds_re = qr/$re_str/;
    }
}
my $MESON_BUILD_DIR = ( $ENV{GIMPGITBUILD__MESON_BUILD_DIR}
        // "to-del--gimpgitbuild--meson-build" );

# See:
# https://github.com/libfuse/libfuse/issues/212
# Ubuntu/etc. places it under $prefix/lib/$arch by default.
my $UBUNTU_MESON_LIBDIR_OVERRIDE = "-D libdir=lib";

my $PAR_JOBS = ( $ENV{GIMPGITBUILD__PAR_JOBS_FLAGS} // '-j4' );

sub _git_sync
{
    my ( $self, $args ) = @_;
    return
qq#$^X -MGit::Sync::App -e "Git::Sync::App->new->run" -- sync origin "$args->{branch}"#;
}

sub _git_build
{
    my $self                 = shift;
    my $args                 = shift;
    my $id                   = $args->{id};
    my $extra_configure_args = ( $args->{extra_configure_args} // [] );

    if ( defined($skip_builds_re) and $id =~ $skip_builds_re )
    {
        return;
    }
    $args->{branch} //= 'master';
    $args->{tag}    //= 'false';

    my $git_co = $args->{git_co};
    if ( !-e "$args->{git_co}" )
    {
        path( $args->{git_co} )->parent->mkpath;
        _do_system( { cmd => [qq#git clone "$args->{url}" "$git_co"#] } );
    }

    my $meson_build_shell_cmd =
qq#mkdir -p "$MESON_BUILD_DIR" && cd "$MESON_BUILD_DIR" && meson --prefix="$args->{prefix}" $UBUNTU_MESON_LIBDIR_OVERRIDE .. && ninja $PAR_JOBS && ninja $PAR_JOBS test && ninja $PAR_JOBS install#;
    my $autoconf_build_shell_cmd =
qq#NOCONFIGURE=1 ./autogen.sh && ./configure @{$extra_configure_args} --prefix="$args->{prefix}" && make $PAR_JOBS && @{[_check()]} && make install#;
    my $sync_cmd = $self->_git_sync( { branch => $args->{branch}, } );
    _do_system(
        {
            cmd => [
qq#cd "$git_co" && git checkout "$args->{branch}" && ( $args->{tag} || $sync_cmd ) && #
                    . (
                    ( $self->{mode} eq 'clean' ) ? "git clean -dxf ."
                    : (
                          $args->{use_meson} ? $meson_build_shell_cmd
                        : $autoconf_build_shell_cmd
                    )
                    )
            ]
        }
    );
    return;
}

sub _which_xvfb_run
{
    my $path = which('xvfb-run');
    if ( not defined($path) )
    {
        die
"Cannot find xvfb-run ! It is required for tests to succeed: see https://gitlab.gnome.org/GNOME/gimp/-/issues/2884";
    }
    return;
}

sub _ascertain_lack_of_gtk_warnings
{
    my $path = which('gvim');
    if ( defined($path) )
    {
        my $stderr = `"$path" -u NONE -U NONE -f /dev/null +q 2>&1`;
        if ( $stderr =~ /\S/ )
        {
            die
"There may be gtk warnings (e.g: in KDE Plasma 5 on Fedora 32 ). Please fix them.";
        }
    }
    return;
}

sub execute
{
    my ( $self, $opt, $args ) = @_;

    my $mode = ( $opt->{mode} || 'build' );
    if ( not( ( $mode eq 'clean' ) or ( $mode eq 'build' ) ) )
    {
        die "Unsupported mode '$mode'!";
    }

    my $fh  = \*STDIN;
    my $obj = App::gimpgitbuild::API::GitBuild->new;

    my $HOME = $obj->home_dir;
    my $env  = $obj->new_env;
    $ENV{PATH}            = $env->{PATH};
    $ENV{PKG_CONFIG_PATH} = $env->{PKG_CONFIG_PATH};
    $ENV{XDG_DATA_DIRS}   = $env->{XDG_DATA_DIRS};
    _which_xvfb_run();
    _ascertain_lack_of_gtk_warnings();
    $self->{mode} = $mode;
    my $base_src_dir = $obj->base_git_clones_dir;

    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';
    $self->_git_build(
        {
            id        => "babl",
            git_co    => "$base_src_dir/babl/git/babl",
            url       => "$GNOME_GIT/babl",
            prefix    => $obj->babl_p,
            use_meson => 1,
        }
    );
    $self->_git_build(
        {
            id        => "gegl",
            git_co    => "$base_src_dir/gegl/git/gegl",
            url       => "$GNOME_GIT/gegl",
            prefix    => $obj->gegl_p,
            use_meson => 1,
        }
    );
    $self->_git_build(
        {
            id        => "libmypaint",
            git_co    => "$base_src_dir/libmypaint/git/libmypaint",
            url       => "https://github.com/mypaint/libmypaint.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.6.1",
            tag       => "true",
        }
    );
    $self->_git_build(
        {
            id        => "mypaint-brushes",
            git_co    => "$base_src_dir/libmypaint/git/mypaint-brushes",
            url       => "https://github.com/Jehan/mypaint-brushes.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.3.x",
        }
    );

    my $KEY        = 'GIMPGITBUILD__BUILD_GIMP_USING_MESON';
    my $GIMP_BUILD = ( exists( $ENV{$KEY} ) ? $ENV{$KEY} : 1 );

# autoconf_git_build "$base_src_dir/git/gimp" "$GNOME_GIT"/gimp "$HOME/apps/gimp-devel"
    $self->_git_build(
        {
            id                   => "gimp",
            extra_configure_args => [ qw# --enable-debug #, ],
            git_co               => "$base_src_dir/git/gimp",
            url                  => "$GNOME_GIT/gimp",
            prefix               => $obj->gimp_p,
            use_meson            => $GIMP_BUILD,
        }
    );

    use Term::ANSIColor qw/ colored /;
    print colored( [ $ENV{HARNESS_SUMMARY_COLOR_SUCCESS} || 'bold green' ],
        "\n== Success ==\n\n" );
    return;
}

1;

__END__

=head1 NAME

gimpgitbuild build - command line utility to automatically build GIMP and its dependencies from git.

=cut
