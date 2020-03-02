package App::gimpgitbuild::Command::env;

use strict;
use warnings;
use 5.014;

use App::gimpgitbuild -command;

use Path::Tiny qw/ path tempdir tempfile cwd /;

use App::gimpgitbuild::API::GitBuild ();

sub description
{
    return "set the environment for using or building GIMP-from-git";
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
