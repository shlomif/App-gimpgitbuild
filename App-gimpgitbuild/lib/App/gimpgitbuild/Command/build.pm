package App::gimpgitbuild::Command::build;

use strict;
use warnings;
use autodie;
use 5.014;

use App::gimpgitbuild -command;

use File::Which qw/ which /;

use App::gimpgitbuild::API::GitBuild ();
use App::gimpgitbuild::API::Worker   ();
use Git::Sync::App                   ();

sub _process_executor
{
    my $self = shift;

    if (@_)
    {
        $self->{_process_executor} = shift;
    }

    return $self->{_process_executor};
}

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
    return ( [ "mode=s", "Mode (e.g: \"clean\")" ],
        [ "process-exe=s", qq#Process executor (= "sh" or "perl")#, ] );

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

    my $_process_executor = ( $opt->{process_exe} || 'perl' );
    if (
        not(   ( $_process_executor eq 'sh' )
            or ( $_process_executor eq 'perl' ) )
        )
    {
        die "Unsupported process-exe '$_process_executor'!";
    }

    my $fh     = \*STDIN;
    my $obj    = App::gimpgitbuild::API::GitBuild->new;
    my $worker = App::gimpgitbuild::API::Worker->new;
    $worker->_api_obj($obj);
    $worker->_mode($mode);
    $worker->_process_executor($_process_executor);

    my $HOME = $obj->home_dir;
    my $env  = $obj->new_env;
    $ENV{PATH}            = $env->{PATH};
    $ENV{PKG_CONFIG_PATH} = $env->{PKG_CONFIG_PATH};
    $ENV{XDG_DATA_DIRS}   = $env->{XDG_DATA_DIRS};
    _which_xvfb_run();
    _ascertain_lack_of_gtk_warnings();

    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';
    $worker->_git_build(
        {
            id                  => "babl",
            git_checkout_subdir => "babl/git/babl",
            url                 => "$GNOME_GIT/babl",
            prefix              => $obj->babl_p,
            use_meson           => 1,
        }
    );
    $worker->_git_build(
        {
            id                  => "gegl",
            git_checkout_subdir => "gegl/git/gegl",
            url                 => "$GNOME_GIT/gegl",
            prefix              => $obj->gegl_p,
            use_meson           => 1,
        }
    );
    $worker->_git_build(
        {
            id                  => "libmypaint",
            git_checkout_subdir => "libmypaint/git/libmypaint",
            url                 => "https://github.com/mypaint/libmypaint.git",
            prefix              => $obj->mypaint_p,
            use_meson           => 0,
            branch              => "v1.6.1",
            tag                 => "true",
        }
    );
    $worker->_git_build(
        {
            id                  => "mypaint-brushes",
            git_checkout_subdir => "libmypaint/git/mypaint-brushes",
            url       => "https://github.com/Jehan/mypaint-brushes.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.3.x",
        }
    );

    my $KEY                    = 'GIMPGITBUILD__BUILD_GIMP_USING_MESON';
    my $BUILD_GIMP_USING_MESON = ( exists( $ENV{$KEY} ) ? $ENV{$KEY} : 1 );

    $worker->_git_build(
        {
            id                   => "gimp",
            extra_configure_args => [ qw# --enable-debug #, ],
            git_checkout_subdir  => "git/gimp",
            url                  => "$GNOME_GIT/gimp",
            prefix               => $obj->gimp_p,
            use_meson            => $BUILD_GIMP_USING_MESON,
            on_failure           => sub {
                my ($args) = @_;
                my $Err = $args->{exception};
                if ( !$BUILD_GIMP_USING_MESON )
                {
                    die $Err;
                }
                STDERR->print( $Err, "\n" );
                STDERR->print(<<"EOF");
Meson-using builds of GIMP are known to be error prone. Please try setting
the "$KEY" environment variable to "0", and run gimpgitbuild again, e.g using:

    export $KEY="0"

EOF
                die "Meson build failure";
            },
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
