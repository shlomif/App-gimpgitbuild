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

sub _ascertain_xvfb_run_presence
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

sub _ascertain_gjs_presence
{
    my $path = which('gjs');
    if ( not defined($path) )
    {
        die
"gjs must be present for GIMP's tests to succeed - please install it (see: https://gitlab.gnome.org/GNOME/gimp/-/issues/7341 )";
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

    my $worker = App::gimpgitbuild::API::Worker->new(
        { _mode => $mode, _process_executor => $_process_executor, } );

    my $env = App::gimpgitbuild::API::GitBuild->new()->new_env();
    $ENV{LD_LIBRARY_PATH} = $env->{LD_LIBRARY_PATH};
    $ENV{PATH}            = $env->{PATH};
    $ENV{PKG_CONFIG_PATH} = $env->{PKG_CONFIG_PATH};
    $ENV{XDG_DATA_DIRS}   = $env->{XDG_DATA_DIRS};
    _ascertain_xvfb_run_presence();
    _ascertain_lack_of_gtk_warnings();
    _ascertain_gjs_presence();

    $worker->_run_the_mode_on_all_repositories();

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
