package App::gimpgitbuild::Command::cleanbuild;

use strict;
use warnings;
use autodie;
use 5.014;

use App::gimpgitbuild -command;

use File::Which qw/ which /;

use App::gimpgitbuild::API::GitBuild ();
use App::gimpgitbuild::API::Worker   ();

sub description
{
    return "clean the GIMP build checkouts";
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

sub execute
{
    my ( $self, $opt, $args ) = @_;

    my $mode              = 'clean';
    my $_process_executor = 'perl';

    my $obj    = App::gimpgitbuild::API::GitBuild->new;
    my $worker = App::gimpgitbuild::API::Worker->new;
    $worker->_api_obj($obj);
    $worker->_mode($mode);
    $worker->_process_executor($_process_executor);

    $worker->_run_the_mode_on_all_repositories();

    use Term::ANSIColor qw/ colored /;
    print colored( [ $ENV{HARNESS_SUMMARY_COLOR_SUCCESS} || 'bold green' ],
        "\n== Success ==\n\n" );
    return;
}

1;

__END__

=head1 NAME

gimpgitbuild cleanbuild - clean the build checkouts / working copies.

=cut
