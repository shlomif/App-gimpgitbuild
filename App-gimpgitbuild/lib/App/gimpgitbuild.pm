# ABSTRACT: generate charts on the command line.
package App::CSV2Chart;

use strict;
use warnings;

use App::Cmd::Setup -app;

1;

__END__

=head1 NAME

csv2chart - command line utility to convert CSV data to a graphical chart


=head1 SYNOPSIS

    ( echo "time,value" ; echo -n $'1,24\n2,36\n3,1977') | \
        csv2chart xlsx --output spreadsheet.xlsx
    gnumeric ./spreadsheet.xlsx


=head1 SEE ALSO

=over 4

=item * L<https://csvkit.readthedocs.io/>

=item * L<https://github.com/watson/chart-csv>

But see L<https://github.com/watson/chart-csv/issues/4> .

=item * L<Text::CSV>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2019 by Shlomi Fish

This program is distributed under the MIT / Expat License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut
