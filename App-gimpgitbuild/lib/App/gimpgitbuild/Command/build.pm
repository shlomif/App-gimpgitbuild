package App::gimpgitbuild::Command::build;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

use Path::Tiny qw/ path tempdir tempfile cwd /;

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
    $args->{branch} //= 'master';
    $args->{tag}    //= 'false';

    my $git_co = $args->{git_co};
    if ( !-e "$args->{git_co}" )
    {
        path( $args->{git_co} )->parent->mkpath;
        _do_system( { cmd => [qq#git clone "$args->{url}" "$git_co"#] } );
    }
    my $meson1 =
qq#mkdir -p "build" && cd build && meson --prefix="$args->{prefix}" .. && ninja -j4 && ninja -j4 test && ninja -j4 install#;
    my $autoconf1 =
qq#NOCONFIGURE=1 ./autogen.sh && ./configure --prefix="$args->{prefix}" && make -j4 && @{[_check()]} && make install#;
    _do_system(
        {
            cmd => [
qq#cd "$git_co" && git checkout "$args->{branch}" && ($args->{tag} || git s origin "$args->{branch}") && #
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

    my $fh = \*STDIN;

    my $HOME      = $ENV{HOME};
    my $gegl_p    = "$HOME/apps/graphics/gegl";
    my $babl_p    = "$HOME/apps/graphics/babl";
    my $mypaint_p = "$HOME/apps/graphics/libmypaint";
    $ENV{PATH}            = "$gegl_p/bin:$ENV{PATH}";
    $ENV{PKG_CONFIG_PATH} = join(
        ":",
        (
            map {
                my $p = $_;
                map { "$p/$_/pkgconfig" } qw# share lib64 lib  #
            } ( $babl_p, $gegl_p, $mypaint_p )
        ),
        ( $ENV{PKG_CONFIG_PATH} // '' )
    );
    $ENV{XDG_DATA_DIRS} =
"$gegl_p/share:$mypaint_p/share:$mypaint_p/share/pkgconfig:$babl_p/share:$ENV{XDG_DATA_DIRS}";

    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';
    _git_build(
        {
            git_co    => "$HOME/Download/unpack/graphics/gimp/babl/git/babl",
            url       => "$GNOME_GIT/babl",
            prefix    => "$babl_p",
            use_meson => 1,
        }
    );
    _git_build(
        {
            git_co    => "$HOME/Download/unpack/graphics/gimp/gegl/git/gegl",
            url       => "$GNOME_GIT/gegl",
            prefix    => "$gegl_p",
            use_meson => 1,
        }
    );
    _git_build(
        {
            git_co =>
                "$HOME/Download/unpack/graphics/gimp/libmypaint/git/libmypaint",
            url       => "https://github.com/mypaint/libmypaint.git",
            prefix    => "$mypaint_p",
            use_meson => 0,
            branch    => "v1.3.0",
            tag       => "true",
        }
    );
    _git_build(
        {
            git_co =>
"$HOME/Download/unpack/graphics/gimp/libmypaint/git/mypaint-brushes",
            url       => "https://github.com/Jehan/mypaint-brushes.git",
            prefix    => "$mypaint_p",
            use_meson => 0,
            branch    => "v1.3.x",
        }
    );

# autoconf_git_build "$HOME/Download/unpack/graphics/gimp/git/gimp" "$GNOME_GIT"/gimp "$HOME/apps/gimp-devel"
    _git_build(
        {
            git_co    => "$HOME/Download/unpack/graphics/gimp/git/gimp",
            url       => "$GNOME_GIT/gimp",
            prefix    => "$HOME/apps/gimp-devel",
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
