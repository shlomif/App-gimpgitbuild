package App::CSV2Chart::Command::svg;

use strict;
use warnings;
use 5.014;

use App::CSV2Chart -command;
use App::CSV2Chart::API::ToXLSX ();

use Path::Tiny qw/ path tempdir tempfile cwd /;

sub description
{
    return "Generate .svg";
}

sub abstract
{
    return shift->description();
}

sub opt_spec
{
    return (
        [ "output|o=s", "Output path" ],
        [ "title=s",    "Chart Title" ],
        [ 'exec|e=s@',  "Execute command on the output" ]
    );
}

sub execute
{
    my ( $self, $opt, $args ) = @_;

    my $output_fn = $opt->{output};
    my $exe       = $opt->{exec} // [];

    my $fh = \*STDIN;

    my $dir = tempdir();

    if ( "$dir" =~ /%/ )
    {
        die "Invalid dir path $dir contains percent signs";
    }

    my $xlsx = $dir->child("temp.xlsx");

    App::CSV2Chart::API::ToXLSX::csv_to_xlsx(
        {
            input_fh  => $fh,
            output_fn => "$xlsx",
            title     => $opt->{title},
        }
    );

    my $svg_fn = $dir->child("out%.svg");
    if (
        system(
            "ssconvert", "--export-graphs",
            "$xlsx", ( "$svg_fn" =~ s/%/%%/r )
        )
        )
    {
        die "ssconvert failed";
    }

    # Use ->copy instead of ->move because rename does
    # not handle cross-partition moves.
    $svg_fn->copy($output_fn);

    if (@$exe)
    {
        system( @$exe, $output_fn );
    }

    return;
}

1;

__END__

=head1 NAME

csv2chart svg - generate an .svg file of a chart from CSV data (requires a recent version of
gnumeric's ssconvert utility).

=cut
