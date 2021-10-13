package App::gimpgitbuild::Command::cleanbuild;

use strict;
use warnings;
use autodie;
use 5.014;

use App::gimpgitbuild -command;

use App::gimpgitbuild::API::Worker ();

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

    my $worker = App::gimpgitbuild::API::Worker->new(
        { _mode => 'clean', _process_executor => 'perl', } );

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
