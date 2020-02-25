package App::gimpgitbuild::Command::env;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

use Path::Tiny qw/ path tempdir tempfile cwd /;

use App::gimpgitbuild::API::GitBuild ();

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

    my $obj = App::gimpgitbuild::API::GitBuild->new;

    my $env = $obj->new_env;
    print <<"EOF";
export PATH="$env->{PATH}" ;
export PKG_CONFIG_PATH="$env->{PKG_CONFIG_PATH}" ;
export XDG_DATA_DIRS="$env->{XDG_DATA_DIRS}" ;
EOF

    return;
}

1;

__END__

=head1 NAME

gimpgitbuild env - set the preferred environment in the shell.

=head1 SYNOPSIS

    # In your sh-compatible shell:
    eval "$(gimpgitbuild env)"

=cut
