package App::gimpgitbuild::Command::build;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

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
    return ();

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

sub _git_build
{
    my $args = shift;
    my $id   = $args->{id};

    my $KEY = "GIMPGITBUILD__SKIP_BUILDS_RE";
    if ( exists $ENV{$KEY} )
    {
        my $re = $ENV{$KEY};
        if ( $id =~ /$re/ )
        {
            return;
        }
    }
    $args->{branch} //= 'master';
    $args->{tag}    //= 'false';

    my $git_co = $args->{git_co};
    if ( !-e "$args->{git_co}" )
    {
        path( $args->{git_co} )->parent->mkpath;
        _do_system( { cmd => [qq#git clone "$args->{url}" "$git_co"#] } );
    }

    # See:
    # https://github.com/libfuse/libfuse/issues/212
    # Ubuntu/etc. places it under $prefix/lib/$arch by default.
    my $UBUNTU_MESON_LIBDIR_OVERRIDE = "-D libdir=lib";
    my $MESON_BUILD_DIR              = ( $ENV{GIMPGITBUILD__MESON_BUILD_DIR}
            // "to-del--gimpgitbuild--meson-build" );
    my $PAR_JOBS = ( $ENV{GIMPGITBUILD__PAR_JOBS_FLAGS} // '-j4' );
    my $meson1 =
qq#mkdir -p "$MESON_BUILD_DIR" && cd "$MESON_BUILD_DIR" && meson --prefix="$args->{prefix}" $UBUNTU_MESON_LIBDIR_OVERRIDE .. && ninja $PAR_JOBS && ninja $PAR_JOBS test && ninja $PAR_JOBS install#;
    my $autoconf1 =
qq#NOCONFIGURE=1 ./autogen.sh && ./configure --prefix="$args->{prefix}" && make $PAR_JOBS && @{[_check()]} && make install#;
    _do_system(
        {
            cmd => [
qq#cd "$git_co" && git checkout "$args->{branch}" && ($args->{tag} || $^X -MGit::Sync::App -e "Git::Sync::App->new->run" -- sync origin "$args->{branch}") && #
                    . ( $args->{use_meson} ? $meson1 : $autoconf1 )
            ]
        }
    );
    return;
}

sub execute
{
    my ( $self, $opt, $args ) = @_;

    my $output_fn = $opt->{output};
    my $exe       = $opt->{exec} // [];

    my $fh  = \*STDIN;
    my $obj = App::gimpgitbuild::API::GitBuild->new;

    my $HOME = $obj->home_dir;
    my $env  = $obj->new_env;
    $ENV{PATH}            = $env->{PATH};
    $ENV{PKG_CONFIG_PATH} = $env->{PKG_CONFIG_PATH};
    $ENV{XDG_DATA_DIRS}   = $env->{XDG_DATA_DIRS};
    my $base_src_dir = $obj->base_git_clones_dir;

    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';
    _git_build(
        {
            id        => "babl",
            git_co    => "$base_src_dir/babl/git/babl",
            url       => "$GNOME_GIT/babl",
            prefix    => $obj->babl_p,
            use_meson => 1,
        }
    );
    _git_build(
        {
            id        => "gegl",
            git_co    => "$base_src_dir/gegl/git/gegl",
            url       => "$GNOME_GIT/gegl",
            prefix    => $obj->gegl_p,
            use_meson => 1,
        }
    );
    _git_build(
        {
            id        => "libmypaint",
            git_co    => "$base_src_dir/libmypaint/git/libmypaint",
            url       => "https://github.com/mypaint/libmypaint.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.3.0",
            tag       => "true",
        }
    );
    _git_build(
        {
            id        => "mypaint-brushes",
            git_co    => "$base_src_dir/libmypaint/git/mypaint-brushes",
            url       => "https://github.com/Jehan/mypaint-brushes.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.3.x",
        }
    );

# autoconf_git_build "$base_src_dir/git/gimp" "$GNOME_GIT"/gimp "$HOME/apps/gimp-devel"
    _git_build(
        {
            id        => "gimp",
            git_co    => "$base_src_dir/git/gimp",
            url       => "$GNOME_GIT/gimp",
            prefix    => $obj->gimp_p,
            use_meson => 1,
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
