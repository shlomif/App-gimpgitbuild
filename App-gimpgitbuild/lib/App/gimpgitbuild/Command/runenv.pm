package App::gimpgitbuild::Command::runenv;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

use Path::Tiny qw/ path tempdir tempfile cwd /;

use App::gimpgitbuild::API::GitBuild ();

sub description
{
    return "set the environment for running GIMP-from-git";
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

    my $output_fn = $opt->{output};
    my $exe       = $opt->{exec} // [];

    my $obj = App::gimpgitbuild::API::GitBuild->new;

    my $env = $obj->new_env;
    print <<"EOF";
export LD_LIBRARY_PATH="$env->{LD_LIBRARY_PATH}" ;
EOF

    return;
}

1;

__END__

=head1 NAME

gimpgitbuild runenv - set the environment in the shell for running the gimp-from-git
installation.

=head1 SYNOPSIS

    # In your sh-compatible shell:
    eval "$(gimpgitbuild runenv)"

=cut
